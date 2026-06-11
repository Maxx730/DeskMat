# Plan: Eve Online Widget

## Goal

Add a 2-cell wide `EveWidget` that shows basic Eve Online character info — portrait, online status, current location, active ship, wallet balance, and current skill training. The player authenticates once via Eve SSO (OAuth 2.0 + PKCE) through a button in Settings. Tokens are stored in Keychain and refreshed automatically.

---

## Current State

- No Eve integration exists
- `DockWidget(cells: 2, ...)` is the standard 2x widget wrapper (128×64 px)
- `WeatherWidget` is the closest reference: `@Observable` service class, `@AppStorage` show-toggle, wired in `ContentView` and `SettingsView`
- Eve's developer portal **does not accept custom URL schemes** (`deskmat://`) — only `http://` or `https://` redirect URIs are valid
- Auth uses a **local HTTP server** on a fixed port (`25734`) to catch the OAuth callback; browser is opened with `NSWorkspace.shared.open()`
- `Keychain` access uses `Security.framework` (already linked in any macOS target)

---

## Widget Layout (128×64 px)

```
┌──────────────────────────────────────────────┐
│  [portrait]  Maximus K.         ● Online     │
│    40×40     Jita · Rifter                   │
│              985.4M ISK                      │
│              Spaceship Cmd IV · 2d 4h        │
└──────────────────────────────────────────────┘
```

If not authenticated:
```
┌──────────────────────────────────────────────┐
│                                              │
│         Connect Eve Account →                │
│                                              │
└──────────────────────────────────────────────┘
```

---

## Phases

---

### Phase 1 — EveAuthService: OAuth + Keychain

**New file:** `DeskMat/EveAuthService.swift`

#### Responsibilities

- Spin up a temporary local HTTP server on port `25734` to receive the OAuth callback
- Open the Eve SSO authorize URL in the user's default browser via `NSWorkspace.shared.open()`
- Exchange the auth code for access + refresh tokens
- Refresh the access token when it expires (20-minute TTL)
- Store/load tokens and character metadata from Keychain
- Expose `isAuthenticated`, `characterId`, `characterName` as observable state

#### Key properties

```swift
@Observable
final class EveAuthService {
    var isAuthenticated: Bool = false
    var characterId: Int = 0
    var characterName: String = ""

    private(set) var accessToken: String = ""
    private var refreshToken: String = ""
    private var tokenExpiry: Date = .distantPast

    static let clientId     = "YOUR_CLIENT_ID"   // from developers.eveonline.com
    static let redirectURI  = "http://localhost:25734/callback"
    static let callbackPort = 25734
    static let scopes = [
        "esi-location.read_online.v1",
        "esi-location.read_location.v1",
        "esi-location.read_ship_type.v1",
        "esi-wallet.read_character_wallet.v1",
        "esi-skills.read_skillqueue.v1"
    ]
}
```

#### PKCE helpers (private)

```swift
// Generate 32-byte random code verifier → base64url
// SHA-256(verifier) → base64url code challenge
private func generatePKCE() -> (verifier: String, challenge: String)
```

#### Local callback server

A lightweight `LocalCallbackServer` helper that:
1. Binds a `NWListener` on TCP port `25734`
2. Waits for a single inbound `GET /callback?code=...&state=...` request
3. Writes a minimal HTTP 200 response: `"Authentication successful. Return to DeskMat."`
4. Resolves an `AsyncStream` or `CheckedContinuation` with the extracted `code` and `state`
5. Shuts the listener down immediately after

```swift
final class LocalCallbackServer {
    // start() → AsyncStream<(code: String, state: String)>
    // Listens on port 25734, yields one value, then cancels itself
}
```

Using `NWListener` from `Network.framework` (already available, no extra dependency).

#### Auth flow

```swift
func connect() async throws {
    let (verifier, challenge) = generatePKCE()
    let state = UUID().uuidString

    // 1. Build authorize URL:
    //    https://login.eveonline.com/v2/oauth/authorize
    //      ?response_type=code
    //      &client_id=CLIENT_ID
    //      &redirect_uri=http://localhost:25734/callback
    //      &scope=<joined scopes>
    //      &code_challenge=CHALLENGE
    //      &code_challenge_method=S256
    //      &state=STATE

    // 2. Start local server — suspends until callback arrives
    let server = LocalCallbackServer()
    let callbackTask = Task { await server.start() }

    // 3. Open browser
    NSWorkspace.shared.open(authorizeURL)

    // 4. Await the code from the local server
    let (code, returnedState) = try await callbackTask.value
    guard returnedState == state else { throw EveAuthError.stateMismatch }

    // 5. Exchange code → tokens
    // POST https://login.eveonline.com/v2/oauth/token
    //   grant_type=authorization_code, client_id, code, code_verifier

    // 6. Decode JWT sub → character_id ("CHARACTER:EVE:<id>")
    // 7. GET /characters/{character_id}/ → character name
    // 8. Save all to Keychain, update observable properties
}
```

No `presentationAnchor` needed — the browser handles the UI entirely.

#### Token refresh

```swift
func validAccessToken() async throws -> String {
    if Date() < tokenExpiry.addingTimeInterval(-60) { return accessToken }
    // POST refresh_token grant to https://login.eveonline.com/v2/oauth/token
    // Update accessToken, tokenExpiry, and Keychain entry
}
```

#### Keychain storage

Use `kSecClassGenericPassword` with `service = "com.cepholotech.deskmat.eve"` and separate `account` keys:
- `"refreshToken"` → refresh token string
- `"accessToken"` → current access token
- `"characterId"` → character ID string
- `"characterName"` → character name string
- `"tokenExpiry"` → ISO8601 expiry string

#### Disconnect

```swift
func disconnect() {
    // Delete all Keychain entries for service "com.cepholotech.deskmat.eve"
    // Reset all observable properties to defaults
}
```

---

### Phase 2 — EveService: fetch character data

**New file:** `DeskMat/EveService.swift`

#### Responsibilities

- Fetch all data needed by the widget using the auth service
- Resolve integer IDs (solar system, station, ship type, skill) to human-readable names
- Cache name lookups in memory (they never change)
- Expose widget-ready strings as observable state

#### Key properties

```swift
@Observable
final class EveService {
    var isOnline: Bool = false
    var lastSeen: Date? = nil
    var locationName: String = ""       // "Jita"
    var shipName: String = ""           // "Rifter"
    var walletFormatted: String = ""    // "985.4M ISK"
    var trainingSkill: String = ""      // "Spaceship Command IV"
    var trainingRemaining: String = ""  // "2d 4h"
    var isLoading: Bool = false

    private var nameCache: [Int: String] = [:]
    let auth: EveAuthService
}
```

#### Fetch method

```swift
func refresh() async {
    guard auth.isAuthenticated else { return }
    isLoading = true
    let token = try? await auth.validAccessToken()
    let id = auth.characterId

    async let online   = fetchOnline(id: id, token: token)
    async let location = fetchLocation(id: id, token: token)
    async let ship     = fetchShip(id: id, token: token)
    async let wallet   = fetchWallet(id: id, token: token)
    async let skill    = fetchSkillQueue(id: id, token: token)

    // Await all, update published properties
    isLoading = false
}
```

#### Endpoints called

| Method | ESI path | Produces |
|---|---|---|
| `fetchOnline` | `GET /characters/{id}/online/` | `isOnline`, `lastSeen` |
| `fetchLocation` | `GET /characters/{id}/location/` → resolve system/station name | `locationName` |
| `fetchShip` | `GET /characters/{id}/ship/` → resolve type name | `shipName` |
| `fetchWallet` | `GET /characters/{id}/wallet/` | `walletFormatted` |
| `fetchSkillQueue` | `GET /characters/{id}/skillqueue/` → resolve skill name | `trainingSkill`, `trainingRemaining` |

#### Universe name resolution

```swift
private func resolveName(typeId: Int, token: String?) async -> String {
    if let cached = nameCache[typeId] { return cached }
    // GET https://esi.evetech.net/latest/universe/types/{typeId}/
    // or /universe/systems/{id}/ or /universe/stations/{id}/
    // Cache result — these IDs never change
}
```

#### Wallet formatting

```swift
private func formatISK(_ balance: Double) -> String {
    switch balance {
    case 1_000_000_000...: return String(format: "%.1fB ISK", balance / 1_000_000_000)
    case 1_000_000...:     return String(format: "%.1fM ISK", balance / 1_000_000)
    case 1_000...:         return String(format: "%.1fK ISK", balance / 1_000)
    default:               return String(format: "%.0f ISK", balance)
    }
}
```

#### Skill time remaining

```swift
private func formatTimeRemaining(until date: Date) -> String {
    let seconds = Int(date.timeIntervalSinceNow)
    let days = seconds / 86400;  let hours = (seconds % 86400) / 3600
    let mins = (seconds % 3600) / 60
    if days > 0  { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(mins)m" }
    return "\(mins)m"
}
```

---

### Phase 3 — EveWidget UI + ContentView + Settings wiring

**New file:** `DeskMat/EveWidget.swift`

**Modified files:** `ContentView.swift`, `SettingsView.swift`, `AppDelegate+Windows.swift`, `Strings.swift`

#### EveWidget.swift

```swift
struct EveWidget: View {
    static let cellCount = 2
    @State private var eveService: EveService   // holds its own EveAuthService

    var body: some View {
        VStack(spacing: 10) {
            DockWidget(cells: 2, isLoading: eveService.isLoading) {
                if eveService.auth.isAuthenticated {
                    characterContent
                } else {
                    notConnectedContent
                }
            }
            if showLabels {
                Text("Eve Online")
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: DockWidget<EmptyView>.width(for: Self.cellCount))
            }
        }
        .task {
            while !Task.isCancelled {
                await eveService.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}
```

#### Character content view

```swift
private var characterContent: some View {
    HStack(spacing: 8) {
        // Portrait
        AsyncImage(url: portraitURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color.white.opacity(0.1)
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6))

        // Info column
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(eveService.auth.characterName)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Circle()
                    .fill(eveService.isOnline ? Color.green : Color.gray)
                    .frame(width: 5, height: 5)
            }
            Text("\(eveService.locationName) · \(eveService.shipName)")
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            Text(eveService.walletFormatted)
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
            if !eveService.trainingSkill.isEmpty {
                Text("\(eveService.trainingSkill) · \(eveService.trainingRemaining)")
                    .font(.system(size: 7, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }

        Spacer(minLength: 0)
    }
    .padding(.horizontal, 8)
}
```

#### Not-connected placeholder

```swift
private var notConnectedContent: some View {
    Text("Connect Eve Account →")
        .font(.system(size: 9, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.7))
        .multilineTextAlignment(.center)
        .padding(8)
}
```

#### ContentView wiring

Add alongside existing widget toggles:

```swift
@AppStorage("showEveWidget") private var showEveWidget = false

// In body:
if entitlements.isPro && showEveWidget {
    EveWidget()
}
```

#### SettingsView: new section in WidgetsSettingsTab

```swift
// Toggle (gated behind Pro like weather)
Toggle(isOn: $showEveWidget) {
    proLabel("Eve Online Widget", isPro: entitlements.isPro)
}
.disabled(!entitlements.isPro)

// Connection UI (shown when toggle is on)
if showEveWidget && entitlements.isPro {
    if eveAuth.isAuthenticated {
        HStack {
            AsyncImage(url: ...) { ... }.frame(width: 24, height: 24).clipShape(Circle())
            Text(eveAuth.characterName).font(.subheadline)
            Spacer()
            Button("Disconnect") { eveAuth.disconnect() }
                .foregroundStyle(.red)
        }
    } else {
        Button("Connect Eve Account") {
            Task { try? await eveAuth.connect() }
        }
    }
}
```

No `presentationAnchor` parameter — `connect()` opens the system browser directly.

`EveAuthService` is injected via `.environment()` from `AppDelegate+Windows.swift`, same as `UpdateService`.

#### AppDelegate+Windows.swift

```swift
// Instantiate alongside updateService
let eveAuth = EveAuthService()

// Add to settings view environment
let settingsView = SettingsView()
    .environment(entitlements)
    .environment(updateService)
    .environment(eveAuth)
```

#### Strings.swift additions

```swift
enum Eve {
    static let widgetLabel    = "Eve Online"
    static let connectButton  = "Connect Eve Account"
    static let disconnectButton = "Disconnect"
    static let notConnected   = "Connect Eve Account →"
    static let online         = "Online"
    static let offline        = "Offline"
}
```

---

## Files Summary

| File | Status | Change |
|---|---|---|
| `EveAuthService.swift` | New | PKCE OAuth, token exchange, Keychain storage, connect/disconnect |
| `EveService.swift` | New | ESI data fetching, name resolution, observable widget state |
| `EveWidget.swift` | New | 2-cell DockWidget with character info or connect placeholder |
| `ContentView.swift` | Modified | Add `showEveWidget` AppStorage + `EveWidget()` in HStack |
| `SettingsView.swift` | Modified | Toggle + connect/disconnect UI in WidgetsSettingsTab |
| `AppDelegate+Windows.swift` | Modified | Instantiate `EveAuthService`, inject into settings environment |
| `Strings.swift` | Modified | Add `Strings.Eve` namespace |

---

## Pre-implementation Requirement

Register the app at `https://developers.eveonline.com` before Phase 1 can be implemented. The **Client ID** from that registration is needed in `EveAuthService.clientId`.

**Callback URL for the developer portal:** `http://localhost:25734/callback`

Scopes to select at registration:
- `esi-location.read_online.v1`
- `esi-location.read_location.v1`
- `esi-location.read_ship_type.v1`
- `esi-wallet.read_character_wallet.v1`
- `esi-skills.read_skillqueue.v1`
