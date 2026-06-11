# Plan: Eve Widget — Paged Sub-Widgets

## Goal

Refactor `EveWidget` to host a `PagedContainerView` inside its `DockWidget`, giving it two pages:

- **Page 1 — Pilot** (existing data): character name, online status, location, ship, wallet, skill training
- **Page 2 — Intel** (new data): total skill points, unallocated SP, active industry job count

The widget footprint and `DockWidget(cells: 2)` wrapper stay the same. Adding pages later is a matter of adding a new ESI fetcher and an entry in the `PagedContainerView` builder.

---

## Current State

- `EveWidget` renders a single `characterContent` view inside `DockWidget(cells: 2)`
- `PagedContainerView` exists at `DeskMat/Utilities/PagedContainerView.swift` and is generic over any `View`; it accepts `pageCount`, `showChevrons`, `showDots`, `autoRotate`
- `EveService` already fetches: online status, location, ship name/race, wallet, skill queue, character race, system faction
- Active ESI scopes: `read_online`, `read_location`, `read_ship_type`, `read_character_wallet`, `read_skillqueue`

---

## Page Layouts

### Page 1 — Pilot (existing)

```
[ < ]  Maximus K.               ●  [ > ]
       Jita · Rifter
       985.4M ISK
       Spaceship Cmd IV · 2d 4h
        •  ○
```

### Page 2 — Intel (new)

```
[ < ]  42.5M SP   (+250K unalloc)  [ > ]
       ⚙ 2 active jobs
        ○  •
```

---

## New ESI Scopes Required

The three new endpoints need scopes not currently requested. The user must reconnect (disconnect → connect) to grant them:

| Scope | Endpoint |
|---|---|
| `esi-skills.read_skills.v1` | `/characters/{id}/skills/` |
| `esi-industry.read_character_jobs.v1` | `/characters/{id}/industry/jobs/` |

Add these to `EveAuthService.scopes` before Phase 1 so re-auth picks them up.

---

## Phases

---

### Phase 1 — Add scopes + new ESI fetchers to `EveService`

**Modified file:** `DeskMat/Services/EveService.swift`
**Modified file:** `DeskMat/Services/EveAuthService.swift`

#### New response models (private)

```swift
private struct SkillsResponse: Decodable {
    let total_sp: Int
    let unallocated_sp: Int?
}

private struct IndustryJob: Decodable {
    let status: String   // "active" | "delivered" | "cancelled" | "paused"
}
```

#### New published properties on `EveService`

```swift
private(set) var totalSP:         String = ""   // "42.5M SP"
private(set) var unallocatedSP:   String = ""   // "+250K unalloc" or ""
private(set) var activeJobs:      Int    = 0
```

#### New fetchers

```swift
private func fetchSkills(id: Int, token: String) async -> (String, String) {
    // GET /characters/{id}/skills/
    // Returns (totalSP formatted, unallocatedSP formatted or "")
}

private func fetchIndustryJobs(id: Int, token: String) async -> Int {
    // GET /characters/{id}/industry/jobs/?include_completed=false
    // Count entries where status == "active"
}
```

#### SP formatting helper

```swift
private func formatSP(_ sp: Int) -> String {
    switch sp {
    case 1_000_000...: return String(format: "%.1fM SP", Double(sp) / 1_000_000)
    case 1_000...:     return String(format: "%.1fK SP", Double(sp) / 1_000)
    default:           return "\(sp) SP"
    }
}
```

#### Wire into `refresh()`

Add `fetchSkills`, `fetchUnreadMail`, `fetchIndustryJobs` to the parallel `async let` block alongside the existing fetchers. Assign results on `MainActor`.

#### `EveAuthService` scope addition

```swift
static let scopes = [
    "esi-location.read_online.v1",
    "esi-location.read_location.v1",
    "esi-location.read_ship_type.v1",
    "esi-wallet.read_character_wallet.v1",
    "esi-skills.read_skillqueue.v1",
    // new:
    "esi-skills.read_skills.v1",
    "esi-mail.read_mail.v1",
    "esi-industry.read_character_jobs.v1"
]
```

---

### Phase 2 — Refactor `EveWidget` to use `PagedContainerView`

**Modified file:** `DeskMat/Widgets/Eve/EveWidget.swift`

Replace the single `characterContent` call inside `DockWidget` with a `PagedContainerView(pageCount: 2, showDots: true)`. Keep the hologram shader background and theme logic unchanged.

#### Updated body structure

```swift
DockWidget(cells: 2, isLoading: eveService.isLoading, ...) {
    if eveService.auth.isAuthenticated {
        PagedContainerView(pageCount: 2, showChevrons: true, showDots: true) { page in
            switch page {
            case 0: pilotPage
            case 1: intelPage
            default: EmptyView()
            }
        }
    } else {
        notConnectedContent
    }
}
```

#### `pilotPage` (extracted from existing `characterContent`)

Same content as the current `characterContent` view — no data changes. Just rename and ensure it fills the available width between chevrons (remove explicit `.padding(.horizontal, 16)` and rely on the pager's layout).

#### `intelPage` (new)

```swift
private var intelPage: some View {
    VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 4) {
            Text(eveService.totalSP)
                .font(.custom("Exo 2", size: 11).weight(.semibold))
                .foregroundStyle(effectiveTheme.labelTint)
            if !eveService.unallocatedSP.isEmpty {
                Text(eveService.unallocatedSP)
                    .font(.custom("Exo 2", size: 8))
                    .foregroundStyle(effectiveTheme.labelTint.opacity(0.55))
            }
        }
        if eveService.activeJobs > 0 {
            Label("\(eveService.activeJobs) active job\(eveService.activeJobs == 1 ? "" : "s")",
                  systemImage: "hammer")
                .font(.custom("Exo 2", size: 8))
                .foregroundStyle(effectiveTheme.labelTint.opacity(0.75))
        }
        if eveService.activeJobs == 0 && eveService.totalSP.isEmpty {
            Text("No intel")
                .font(.custom("Exo 2", size: 8))
                .foregroundStyle(effectiveTheme.labelTint.opacity(0.4))
        }
    }
    .padding(.horizontal, 4)
}
```

---

## Files Changed

| File | Change |
|---|---|
| `DeskMat/Services/EveAuthService.swift` | Add 3 new scopes to `scopes` array |
| `DeskMat/Services/EveService.swift` | New response models, 3 new published properties, 2 new fetchers, SP formatter, wire into `refresh()` |
| `DeskMat/Widgets/Eve/EveWidget.swift` | Wrap authenticated content in `PagedContainerView(pageCount: 2)`, extract `pilotPage`, add `intelPage` |

---

## Notes

- Graceful degradation: if new scopes haven't been granted yet, the two new fetchers will receive 403s and return zero/empty values — `intelPage` will show "No intel" rather than crashing
- The `showDots` dots add ~8pt of vertical space below the page content; verify the hologram shader background still looks correct at the new effective content height
- Adding a third page later requires only: a new fetcher in `EveService`, a new case in the `PagedContainerView` builder, and bumping `pageCount` to 3
