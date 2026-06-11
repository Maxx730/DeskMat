# Exploration: Eve Online Widget

## Overview

Eve Online exposes a REST API called **ESI** (Eve Swagger Interface) at `https://esi.evetech.net`. It follows OpenAPI conventions, returns JSON, and has per-endpoint versioning. The interactive explorer lives at `https://esi.evetech.net/ui/`.

A DeskMat widget would surface a player's current in-game status at a glance — online status, location, active ship, wallet balance, and skill training progress. Most interesting data requires the player to authenticate once; public data (character name, portrait) requires no auth.

---

## Authentication: Eve SSO (OAuth 2.0 with PKCE)

Eve uses standard OAuth 2.0. For a native desktop app, the recommended flow is **Authorization Code + PKCE** — no client secret is hardcoded in the app, which matters for a signed/notarized macOS binary distributed publicly.

### What you register

1. Go to `https://developers.eveonline.com` → **Applications** → **Create New Application**
2. Set **Connection Type** to "Authentication & API Access"
3. Choose scopes (see below)
4. Set a **Callback URL** — for a native app, use a custom URL scheme like `deskmat://eve/callback` registered in `Info.plist`, or `http://localhost:PORT/callback` with a local HTTP server

You get back a **Client ID** (public, safe to ship in the binary). No secret is needed for PKCE.

### The flow

```
1. User clicks "Connect Eve Account"

2. App generates:
     code_verifier  = 32 random bytes (hex or base64url)
     code_challenge = base64url(SHA-256(code_verifier))

3. Open in browser / ASWebAuthenticationSession:
     https://login.eveonline.com/v2/oauth/authorize
       ?response_type=code
       &client_id=YOUR_CLIENT_ID
       &redirect_uri=deskmat://eve/callback
       &scope=esi-location.read_online.v1 esi-location.read_location.v1 ...
       &code_challenge=BASE64URL_CHALLENGE
       &code_challenge_method=S256
       &state=RANDOM_NONCE

4. Eve SSO redirects to:
     deskmat://eve/callback?code=AUTH_CODE&state=NONCE

5. App POST-exchanges:
     POST https://login.eveonline.com/v2/oauth/token
     Content-Type: application/x-www-form-urlencoded

     grant_type=authorization_code
     &client_id=YOUR_CLIENT_ID
     &code=AUTH_CODE
     &code_verifier=CODE_VERIFIER

6. Response:
     {
       "access_token":  "<JWT>",   // valid 20 minutes
       "refresh_token": "<token>", // long-lived, store in Keychain
       "expires_in":    1200,
       "token_type":    "Bearer"
     }

7. Decode the JWT to extract character_id (sub claim = "CHARACTER:EVE:<id>")
```

### Token refresh

Access tokens expire after **20 minutes**. Refresh before making any API call:

```
POST https://login.eveonline.com/v2/oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token
&client_id=YOUR_CLIENT_ID
&refresh_token=STORED_REFRESH_TOKEN
```

The response may include a new refresh token — always replace the stored one.

### What to store (Keychain)

| Key | Value |
|---|---|
| `eve.characterId` | Integer extracted from JWT sub |
| `eve.characterName` | String from `/characters/{id}/` |
| `eve.accessToken` | Current JWT |
| `eve.accessTokenExpiry` | `Date` 20 min after issue |
| `eve.refreshToken` | Long-lived, replace on each refresh |

---

## Scopes

Each authenticated endpoint requires a specific scope declared at registration time. Only request what the widget actually shows — extra scopes create unnecessary friction on the consent screen.

**Recommended minimal set for a status widget:**

| Scope | Data unlocked |
|---|---|
| `esi-location.read_online.v1` | Online/offline status, last login |
| `esi-location.read_location.v1` | Current solar system / station |
| `esi-location.read_ship_type.v1` | Current ship name and type |
| `esi-wallet.read_character_wallet.v1` | ISK balance |
| `esi-skills.read_skillqueue.v1` | Active skill training, finish time |

Optional additions:

| Scope | Data unlocked |
|---|---|
| `esi-skills.read_skills.v1` | Total SP, all trained skills |
| `esi-clones.read_implants.v1` | Active implants |
| `esi-corporations.read_corporation_membership.v1` | Corp details |

---

## Endpoints

### Public (no auth)

#### `GET /characters/{character_id}/`
Cache: 7 days. Returns name, corporation_id, security_status, race, birthday.

```json
{
  "name": "Maximus Kinghorn",
  "corporation_id": 98765432,
  "security_status": 2.5,
  "gender": "male",
  "birthday": "2010-03-12T00:00:00Z"
}
```

#### `GET /characters/{character_id}/portrait/`
Cache: daily (expires 11:05 UTC). Returns image URLs at 64, 128, 256, 512px.

```json
{
  "px128x128": "https://imageserver.eveonline.com/Character/123456789_128.jpg",
  "px512x512": "https://imageserver.eveonline.com/Character/123456789_512.jpg"
}
```

Use `px128x128` for the widget — appropriate resolution, small download.

#### `GET /corporations/{corporation_id}/`
Cache: 1 hour. Returns corp name, ticker, member count, tax rate.

---

### Authenticated

#### `GET /characters/{character_id}/online/`
Scope: `esi-location.read_online.v1` · Cache: **60 seconds**

```json
{
  "online": true,
  "last_login":  "2026-06-09T14:30:00Z",
  "last_logout": "2026-06-09T12:00:00Z",
  "logins": 342
}
```

Best poll rate for a widget: every 60 seconds (matches cache TTL).

#### `GET /characters/{character_id}/location/`
Scope: `esi-location.read_location.v1` · Cache: **5 seconds**

```json
{
  "solar_system_id": 30000142,
  "station_id": 60004623
}
```

`solar_system_id` and `station_id` are integers — resolve them to names via:
- `GET /universe/systems/{system_id}/` → `{ "name": "Jita" }`
- `GET /universe/stations/{station_id}/` → `{ "name": "Jita IV - Moon 4 - Caldari Navy Assembly Plant" }`

Both are public endpoints with long cache TTLs (hours/days). Cache the name lookups locally — they never change.

#### `GET /characters/{character_id}/ship/`
Scope: `esi-location.read_ship_type.v1` · Cache: **5 seconds**

```json
{
  "ship_item_id": 1000000000001,
  "ship_name":    "My Rifter",
  "ship_type_id": 587
}
```

Resolve ship type to a human name via:
`GET /universe/types/{type_id}/` → `{ "name": "Rifter" }`

Again, public + long cache — these rarely change.

#### `GET /characters/{character_id}/wallet/`
Scope: `esi-wallet.read_character_wallet.v1` · Cache: **120 seconds**

Returns a single float: the ISK balance.

```
985432765.50
```

Format for display: `985.4M ISK` or `985,432,765 ISK`.

#### `GET /characters/{character_id}/skillqueue/`
Scope: `esi-skills.read_skillqueue.v1` · Cache: **120 seconds**

Returns an array sorted by queue position. The first entry with `finish_date` is the actively training skill.

```json
[
  {
    "queue_position": 0,
    "skill_id":       3402,
    "finished_level": 4,
    "start_date":     "2026-06-09T10:00:00Z",
    "finish_date":    "2026-06-11T18:30:00Z",
    "training_start_sp": 226275,
    "level_end_sp":      1280000
  }
]
```

Resolve `skill_id` to a name via `GET /universe/types/{type_id}/`. Show "Spaceship Command IV — 2d 4h remaining".

---

## Widget Layout Ideas

### Compact (same size as other widgets)

```
┌─────────────────────────────────┐
│  [portrait 48px]  Maximus K.    │
│                   ● Online      │
│  Jita IV · Caldari Navy Plant   │
│  [Rifter]  985.4M ISK           │
│  Spaceship Cmd IV · 2d 4h left  │
└─────────────────────────────────┘
```

### Minimal (status badge only)

Show portrait + green/gray dot. Tap to expand.

---

## Implementation Architecture (macOS / SwiftUI)

### OAuth callback

Register a custom URL scheme `deskmat` in `Info.plist`:
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array><string>deskmat</string></array>
  </dict>
</array>
```

Handle the callback in `AppDelegate.application(_:open:)`. Extract the `code` parameter from the URL and complete the token exchange.

Alternatively, use `ASWebAuthenticationSession` with `callbackURLScheme: "deskmat"` — this handles the redirect natively without the URL type registration.

```swift
let session = ASWebAuthenticationSession(
    url: authURL,
    callbackURLScheme: "deskmat"
) { callbackURL, error in
    // extract code from callbackURL.queryItems
    // POST exchange
}
session.presentationContextProvider = self
session.start()
```

### Service structure

```swift
@Observable
class EveService {
    var characterName: String = ""
    var isOnline: Bool = false
    var lastLogin: Date? = nil
    var locationName: String = ""
    var shipName: String = ""
    var walletBalance: Double = 0
    var trainingSkillName: String = ""
    var trainingFinishDate: Date? = nil

    private var characterId: Int = 0

    func authenticate() async { /* PKCE flow */ }
    func refresh() async { /* poll all endpoints */ }
    private func refreshToken() async throws { /* token exchange */ }
}
```

### Polling

Different endpoints have different cache TTLs:
- Online status: poll every 60 s
- Location + ship: poll every 30 s (cache is 5 s but no need to be that aggressive)
- Wallet + skills: poll every 120 s

Use separate `Task` loops inside `EveService`, or a single loop with a 30 s interval that only fetches wallet/skills every 4th tick.

---

## Rate Limits

Eve ESI uses a floating-window error rate limiter. The `420 Error Limited` status means you've been cut off temporarily.

Rules to stay safe:
- Always respect the `Expires` header — never poll faster than the cache TTL
- Send `If-None-Match` with the `ETag` value from the previous response — a `304 Not Modified` costs nothing
- Include a descriptive `User-Agent` header: `User-Agent: DeskMat/1.x (max.kinghorn@gmail.com)`
- The ESI status page (`https://esi.evetech.net/status.json`) shows route health — worth checking on startup

---

## What's Needed to Ship

| Item | Notes |
|---|---|
| Developer app registration | `developers.eveonline.com`, takes minutes |
| Client ID | From registration, safe to embed in binary |
| `ASWebAuthenticationSession` | Built into macOS 10.15+, handles the browser OAuth flow |
| Keychain storage | Store refresh token + character metadata |
| PKCE implementation | ~10 lines: random bytes → SHA-256 → base64url |
| Name lookup cache | Solar system, station, ship type, skill names — all public ESI endpoints, cache in-memory or UserDefaults |
| Token refresh logic | Check `accessTokenExpiry` before each request |

No server-side component required. The widget talks directly to ESI from the user's machine.

---

## Open Questions Before Planning

1. **Multiple characters** — should the widget support switching between characters, or lock to one account?
2. **Widget size** — same fixed size as weather/system, or expandable?
3. **Offline handling** — show last-known state with a timestamp, or gray out entirely?
4. **Keychain sharing** — does the Eve character token need to be accessible to any other process, or just DeskMat?
5. **Pro gate** — should the Eve widget be Pro-only like weather, or available to all users?
