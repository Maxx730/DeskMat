# Eve Theme — System Faction Detection

## Problem

Ship race detection is unreliable: many hulls (navy/faction ships, industrials) carry no
`race_id` and dogma attribute 1692 is not universal. Detecting the theme from the solar
system the player is *in* is more stable — empire space systems have a fixed NPC faction
owner that never changes.

## Approach

Use the ESI sovereignty map (`GET /sovereignty/map/`) to look up the `faction_id` of the
player's current solar system and map that to a theme. Fall back to ship race → character
race when the system has no faction (null sec, wormholes, abyssal).

### ESI endpoints

| Endpoint | Auth | Notes |
|---|---|---|
| `GET /characters/{id}/location/` | Bearer | Already called; returns `solar_system_id` |
| `GET /sovereignty/map/` | None | ~7 000 entries; `faction_id` present for NPC-held systems |

### Faction ID → theme mapping

| faction_id | Faction | Theme |
|---|---|---|
| 500001 | Caldari State | `.caldari` |
| 500002 | Minmatar Republic | `.minmatar` |
| 500003 | Amarr Empire | `.amarr` |
| 500004 | Gallente Federation | `.gallente` |
| any other / absent | Pirate / null / WH | fall through to ship race |

### Resolution chain (new)

```
system faction_id → ship race_id → character race_id → .auto (default)
```

### Caching

The sovereignty map is ~400 KB and changes at most every EVE downtime (~24 h). Cache
the full decoded array in memory; re-fetch once per app session (or on next refresh after
>1 hour has elapsed since last fetch).

---

## Phase 1 — Extend EveService

**File:** `DeskMat/Services/EveService.swift`

### 1a — Capture solar_system_id from location fetch

`fetchLocation` currently discards the ID after name resolution. Change its return type
to `(String, Int)` — system name and system ID.

```swift
private func fetchLocation(id: Int, token: String) async -> (String, Int) {
    // decode solar_system_id, resolve name, return (name, solar_system_id)
    // on error return ("", 0)
}
```

Update `refresh()` to unpack both values and store the system ID.

### 1b — Sovereignty model + cache

```swift
private struct SovereigntyEntry: Decodable {
    let system_id: Int
    let faction_id: Int?
}

// In EveService:
private var sovereigntyCache: [Int: Int] = [:]   // system_id → faction_id
private var sovereigntyFetchedAt: Date?
```

### 1c — fetchSystemFaction

```swift
private func fetchSystemFaction(systemId: Int) async -> Int? {
    // Return cached value if available and < 1 hour old
    if let cached = sovereigntyCache[systemId],
       let fetchedAt = sovereigntyFetchedAt,
       Date().timeIntervalSince(fetchedAt) < 3600 {
        return cached == 0 ? nil : cached
    }
    // Fetch full map, rebuild cache
    let data = try await esiRequest(path: "/sovereignty/map/")
    let entries = try esiDecoder.decode([SovereigntyEntry].self, from: data)
    sovereigntyCache = Dictionary(
        uniqueKeysWithValues: entries.compactMap { e in
            guard let f = e.faction_id else { return nil }
            return (e.system_id, f)
        }
    )
    sovereigntyFetchedAt = Date()
    return sovereigntyCache[systemId]
}
```

### 1d — Published property + refresh wiring

Add `private(set) var systemFactionId: Int? = nil` to `EveService`.

In `refresh()`, run `fetchSystemFaction` concurrently with the other fetches (after
location resolves so we have the system ID), then publish the result.

---

## Phase 2 — Update EveWidgetTheme

**File:** `DeskMat/Widgets/Eve/EveWidgetTheme.swift`

Add a second factory that maps ESI faction IDs (500 000-range) to themes:

```swift
static func from(factionId: Int?) -> EveWidgetTheme {
    switch factionId {
    case 500001: return .caldari
    case 500002: return .minmatar
    case 500003: return .amarr
    case 500004: return .gallente
    default:     return .auto
    }
}
```

---

## Phase 3 — Update EveWidget theme resolution

**File:** `DeskMat/Widgets/Eve/EveWidget.swift`

Update `effectiveTheme` to prefer system faction, falling back to ship race then
character race:

```swift
private var effectiveTheme: EveWidgetTheme {
    guard theme == .auto else { return theme }
    let bySystem = EveWidgetTheme.from(factionId: eveService.systemFactionId)
    if bySystem != .auto { return bySystem }
    let byShip = EveWidgetTheme.from(raceId: eveService.shipRaceId)
    if byShip != .auto { return byShip }
    return EveWidgetTheme.from(raceId: eveService.characterRaceId)
}
```

---

## Done

Theme now reflects where the player *is* rather than what they fly. Null/WH space falls
back gracefully to ship race or character race. The sovereignty map is fetched once per
session and cached in memory, adding negligible overhead.
