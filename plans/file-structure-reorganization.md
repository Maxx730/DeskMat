# File Structure Reorganization

## Problem

All 60+ Swift files live in a single flat directory (`DeskMat/`). As the project grows this makes it harder to find files, understand boundaries between features, and onboard new contributors. Files with clear relationships (e.g. `EveWidget`, `EveService`, `EveWidgetTheme`, `EveHologramEffect`) sit unrelated to each other alphabetically.

## Goal

Introduce a real folder hierarchy on disk that groups files by feature and layer. Since all files are in the same Swift module, no `import` changes are needed — moves are purely organizational.

## Target Structure

```
DeskMat/
├── App/                        # Entry point, AppDelegate extensions, panel
│   ├── DeskMatApp.swift
│   ├── DeskMatPanel.swift
│   ├── ContentView.swift
│   ├── AppDelegate+Appearance.swift
│   ├── AppDelegate+AutoHide.swift
│   ├── AppDelegate+FullscreenDetection.swift
│   ├── AppDelegate+Panel.swift
│   └── AppDelegate+Windows.swift
│
├── Core/                       # Shared constants, extensions, utilities
│   ├── AppEnums.swift
│   ├── Strings.swift
│   ├── NotificationNames.swift
│   ├── UserDefaultsExtensions.swift
│   ├── ColorUtils.swift
│   └── ImageUtils.swift
│
├── Services/                   # Observable data/state services
│   ├── EveAuthService.swift
│   ├── EveService.swift
│   ├── LicenseManager.swift
│   ├── LocationService.swift
│   ├── SystemMonitorService.swift
│   ├── UpdateService.swift
│   ├── WeatherService.swift
│   └── WindowStateService.swift
│
├── Dock/                       # Dock items, shortcuts, drag, folders
│   ├── AppShortcut.swift
│   ├── AppShortcutButton.swift
│   ├── AppShortcutStore.swift
│   ├── DockItem.swift
│   ├── DockWidget.swift
│   ├── DragCoordinator.swift
│   ├── DragGhostPanel.swift
│   ├── FolderButton.swift
│   ├── FolderExpansionPanel.swift
│   ├── FolderExpansionView.swift
│   ├── FolderSheet.swift
│   ├── HoverAnimationModifier.swift
│   └── IconPickerButton.swift
│
├── Widgets/                    # Each widget in its own sub-folder
│   ├── Clock/
│   │   └── ClockWidget.swift
│   ├── Eve/
│   │   ├── EveWidget.swift
│   │   ├── EveWidgetTheme.swift
│   │   └── EveHologramEffect.swift
│   ├── Image/
│   │   └── ImageWidget.swift
│   ├── LEDBoard/
│   │   └── LEDBoardWidget.swift
│   ├── System/
│   │   └── SystemWidget.swift
│   └── Weather/
│       ├── WeatherWidget.swift
│       ├── CelestialBody.swift
│       ├── CelestialDialView.swift
│       ├── CloudsView.swift
│       ├── RainView.swift
│       └── SkyGradient.swift
│
├── Shaders/                    # All shader infrastructure and Metal files
│   ├── DockItemShader.swift
│   ├── DockVisualEffect.swift
│   ├── ReactiveBackgroundView.swift
│   ├── WidgetShaderBackground.swift
│   ├── WidgetShaderModifier.swift
│   ├── Shaders.metal
│   └── ReactiveShaders.metal
│
├── Settings/                   # Settings, onboarding, pro UI
│   ├── OnboardingView.swift
│   ├── SettingsView.swift
│   ├── SettingsSection.swift
│   ├── ProBadge.swift
│   └── ShortcutSheet.swift
│
└── Utilities/                  # Reusable low-level view helpers
    ├── FirstMouseClickable.swift
    ├── FirstMouseHostingView.swift
    └── ImageProgressView.swift
```

## Important Notes

- **No import changes needed** — all files are in the same Swift module (`DeskMat`). Moving files does not break any type references.
- **Metal files** — `Shaders.metal` and `ReactiveShaders.metal` must remain in the Xcode target's compile sources. After moving, verify both appear in Build Phases → Compile Sources.
- **Xcode workflow** — use Xcode's project navigator to move files (drag into new group folder). Xcode 15+ moves the file on disk automatically when using folder-backed groups. Do not move files in Finder while Xcode is open.
- **Build after each phase** — catch any broken references before moving on.

---

## Phase 1 — App/ and Core/

Move the app entry point, AppDelegate extensions, and shared constants/utilities. These files have no dependencies on each other and are the lowest risk.

**Files to move into `App/`:**
- DeskMatApp.swift
- DeskMatPanel.swift
- ContentView.swift
- AppDelegate+Appearance.swift
- AppDelegate+AutoHide.swift
- AppDelegate+FullscreenDetection.swift
- AppDelegate+Panel.swift
- AppDelegate+Windows.swift

**Files to move into `Core/`:**
- AppEnums.swift
- Strings.swift
- NotificationNames.swift
- UserDefaultsExtensions.swift
- ColorUtils.swift
- ImageUtils.swift

**Verify:** Build succeeds. No file reference errors.

---

## Phase 2 — Services/

Move all observable service classes. These are standalone and only referenced by views/widgets, not by each other (except EveService referencing EveAuthService, which will move together).

**Files to move into `Services/`:**
- EveAuthService.swift
- EveService.swift
- LicenseManager.swift
- LocationService.swift
- SystemMonitorService.swift
- UpdateService.swift
- WeatherService.swift
- WindowStateService.swift

**Verify:** Build succeeds.

---

## Phase 3 — Dock/

Move all dock interaction files. These are tightly coupled to each other but not to widgets or services directly.

**Files to move into `Dock/`:**
- AppShortcut.swift
- AppShortcutButton.swift
- AppShortcutStore.swift
- DockItem.swift
- DockWidget.swift
- DragCoordinator.swift
- DragGhostPanel.swift
- FolderButton.swift
- FolderExpansionPanel.swift
- FolderExpansionView.swift
- FolderSheet.swift
- HoverAnimationModifier.swift
- IconPickerButton.swift

**Verify:** Build succeeds.

---

## Phase 4 — Widgets/

Move each widget into its own sub-folder. Weather gets the most sub-views so it benefits most from grouping.

**Files to move:**
- `Widgets/Clock/` — ClockWidget.swift
- `Widgets/Eve/` — EveWidget.swift, EveWidgetTheme.swift, EveHologramEffect.swift
- `Widgets/Image/` — ImageWidget.swift
- `Widgets/LEDBoard/` — LEDBoardWidget.swift
- `Widgets/System/` — SystemWidget.swift
- `Widgets/Weather/` — WeatherWidget.swift, CelestialBody.swift, CelestialDialView.swift, CloudsView.swift, RainView.swift, SkyGradient.swift

**Verify:** Build succeeds.

---

## Phase 5 — Shaders/

Move all shader infrastructure together. After moving, manually verify both Metal files appear in Build Phases → Compile Sources.

**Files to move into `Shaders/`:**
- DockItemShader.swift
- DockVisualEffect.swift
- ReactiveBackgroundView.swift
- WidgetShaderBackground.swift
- WidgetShaderModifier.swift
- Shaders.metal
- ReactiveShaders.metal

**Verify:** Build succeeds. Both `.metal` files present in Compile Sources. Shader effects visible at runtime.

---

## Phase 6 — Settings/ and Utilities/

Move the remaining files.

**Files to move into `Settings/`:**
- OnboardingView.swift
- SettingsView.swift
- SettingsSection.swift
- ProBadge.swift
- ShortcutSheet.swift

**Files to move into `Utilities/`:**
- FirstMouseClickable.swift
- FirstMouseHostingView.swift
- ImageProgressView.swift

**Verify:** Build succeeds. Settings window opens correctly. Onboarding flow works.

---

## Done

All files organized. The flat `DeskMat/` directory is now replaced by 8 top-level folders with clear ownership boundaries.
