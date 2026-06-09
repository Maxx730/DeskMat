# Plan: Updates Settings Tab

## Goal

Fill the empty `UpdatesSettingsTab` in Settings with a simple UI that shows the current version, lets the user manually check for updates, and surfaces a download button when a newer version is available.

---

## Current State

- `UpdatesSettingsTab` exists in `SettingsView.swift` but contains only an empty `VStack { Spacer() }`
- `UpdateService` is `@Observable` and lives on `AppDelegate` as `updateService`
- `SettingsView` already receives `LicenseManager` via `.environment(entitlements)` — same pattern applies here
- `UpdateService` exposes: `isChecking`, `isUpdateAvailable`, `latestVersion`, `downloadURL`, `releaseNotes`
- Last check date is stored in `UserDefaults` under `"lastUpdateCheckDate"`

---

## Layout

```
┌───────────────────────────────────┐
│  DeskMat  ·  Version 1.3.8        │  ← app name + current version
│                                   │
│  ╔═══════════════════════════╗    │
│  ║  ✓  You're up to date     ║    │  ← status card (3 states below)
│  ║  1.3.8 is the latest.     ║    │
│  ╚═══════════════════════════╝    │
│                                   │
│        [ Check for Updates ]      │  ← button, disabled while checking
│  Last checked: Today at 10:30 AM  │  ← from UserDefaults
└───────────────────────────────────┘
```

**Status card — 3 states:**

| State | Content |
|---|---|
| Never checked / unknown | Gray · "No update information yet." |
| Up to date | Green checkmark · "You're up to date. X.X.X is the latest." |
| Update available | Accent blue · version name · release notes (if any) · **Download** button |

---

## Phases

---

### Phase 1 — Inject UpdateService into SettingsView

**Files:** `AppDelegate+Windows.swift`, `SettingsView.swift`

#### AppDelegate+Windows.swift

Add `.environment(updateService)` alongside the existing `.environment(entitlements)`:

```swift
let settingsView = SettingsView()
    .environment(entitlements)
    .environment(updateService)
```

#### SettingsView

Add `@Environment(UpdateService.self) private var updateService` at the top of `SettingsView` and pass it into `UpdatesSettingsTab`:

```swift
struct SettingsView: View {
    @Environment(UpdateService.self) private var updateService
    // ...
    UpdatesSettingsTab(updateService: updateService)
        .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
}
```

`UpdatesSettingsTab` receives it as a `let` property — no need for another `@Environment` lookup inside the tab since the service is already resolved.

---

### Phase 2 — UpdatesSettingsTab UI

**File:** `SettingsView.swift` (`UpdatesSettingsTab` struct at the bottom)

#### State needed

```swift
private struct UpdatesSettingsTab: View {
    let updateService: UpdateService

    @State private var lastChecked: Date? = UserDefaults.standard.object(forKey: "lastUpdateCheckDate") as? Date

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    // ...
}
```

#### Full layout

```swift
var body: some View {
    VStack(spacing: 20) {

        // ── App identity ──────────────────────────────────────
        VStack(spacing: 2) {
            Text("DeskMat")
                .font(.headline)
            Text("Version \(currentVersion)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)

        // ── Status card ───────────────────────────────────────
        statusCard
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

        // ── Check button ──────────────────────────────────────
        Button {
            Task {
                await updateService.check(force: true)
                lastChecked = Date()
            }
        } label: {
            if updateService.isChecking {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Checking...")
                }
            } else {
                Text("Check for Updates")
            }
        }
        .disabled(updateService.isChecking)

        // ── Last checked ──────────────────────────────────────
        if let lastChecked {
            Text("Last checked: \(lastChecked.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Spacer()
    }
    .padding(20)
}
```

#### Status card (`@ViewBuilder statusCard`)

```swift
@ViewBuilder
private var statusCard: some View {
    if updateService.isUpdateAvailable {
        // ── Update available ──────────────────────────────────
        VStack(alignment: .leading, spacing: 8) {
            Label("DeskMat \(updateService.latestVersion) Available",
                  systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.accent)
                .font(.subheadline.bold())
            if let notes = updateService.releaseNotes {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            Button("Download") {
                if let url = updateService.downloadURL {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    } else if !updateService.latestVersion.isEmpty {
        // ── Up to date ────────────────────────────────────────
        Label("You're up to date. \(updateService.latestVersion) is the latest.",
              systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .font(.subheadline)
    } else {
        // ── Not yet checked ───────────────────────────────────
        Text("No update information yet.")
            .foregroundStyle(.secondary)
            .font(.subheadline)
    }
}
```

---

## Files Changed

| File | Change |
|---|---|
| `AppDelegate+Windows.swift` | Add `.environment(updateService)` to settings view creation |
| `SettingsView.swift` | Add `@Environment(UpdateService.self)` to `SettingsView`, pass to `UpdatesSettingsTab`, implement the tab UI |

No new files. No new strings needed — all text is inline since it's a single-purpose view.
