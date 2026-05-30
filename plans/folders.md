# Folders — Implementation Plan

Users can group app shortcuts into named folders. A folder appears as a single dock item showing a mini icon grid. Tapping it opens a popover with the full-size app grid where apps can be launched. This is the most architecturally significant feature added to date — it requires changing the dock's core data model from a flat `[AppShortcut]` array to a heterogeneous `[DockItem]` list.

---

## Architecture overview

| Layer | What changes |
|---|---|
| `DockItem.swift` | New file — `AppFolder` struct + `DockItem` enum replacing raw `[AppShortcut]` everywhere |
| `AppShortcutStore` | Migrated to read/write `[DockItem]`; backward-compatible load from old `[AppShortcut]` JSON |
| `FolderButton` | New view — inline dock item showing mini icon grid, opens popover on tap |
| `FolderPopover` | New view — grid of full-size app buttons inside the folder |
| `ContentView` | `shortcuts: [AppShortcut]` → `items: [DockItem]`; `ForEach` branches on `.shortcut` / `.folder` |
| Drag-to-reorder | Updated to operate on `[DockItem]` instead of `[AppShortcut]` |
| Export / Import | `DskmArchive` updated to encode/decode `[DockItem]` |

---

## Phase 1 — Data model

**New file:** `DeskMat/DockItem.swift`

### `AppFolder`

```swift
struct AppFolder: Identifiable, Codable {
    let id: UUID
    var name: String
    var shortcuts: [AppShortcut]   // embedded — each folder owns its items
    var iconFileName: String?      // nil = auto mini-grid; set = custom image

    init(name: String, shortcuts: [AppShortcut] = [], iconFileName: String? = nil) {
        self.id = UUID()
        self.name = name
        self.shortcuts = shortcuts
        self.iconFileName = iconFileName
    }
}
```

Shortcuts are embedded rather than referenced by ID. This keeps serialization simple and means folder items are fully self-contained. `iconFileName` follows the same convention as `AppShortcut.iconFileName` — a filename relative to `AppShortcutStore.iconsDirectory`.

### `DockItem`

```swift
enum DockItem: Identifiable, Codable {
    case shortcut(AppShortcut)
    case folder(AppFolder)

    var id: UUID {
        switch self {
        case .shortcut(let s): return s.id
        case .folder(let f):   return f.id
        }
    }
}
```

`DockItem` conforms to `Codable` via a tagged enum encoding (`type` + `value` keys) so both cases survive JSON round-trips.

---

## Phase 2 — Store migration

**File:** `DeskMat/AppShortcutStore.swift`

Replace `[AppShortcut]` with `[DockItem]` throughout. The key constraint is **backward compatibility** — existing `shortcuts.json` files contain a plain `[AppShortcut]` array and must still load correctly.

### Load strategy

```swift
static func load() -> [DockItem] {
    // Try new [DockItem] format first
    if let items = try? decode([DockItem].self, from: shortcutsFileURL) {
        return items
    }
    // Fall back to legacy [AppShortcut] format — wrap each in .shortcut()
    if let legacy = try? decode([AppShortcut].self, from: shortcutsFileURL) {
        return legacy.map { .shortcut($0) }
    }
    return []
}
```

### Other store methods

- `save(_ items: [DockItem])` — encodes and writes `[DockItem]`
- `deleteIcon(named:)` — iterate all `.shortcut` cases across top-level items and folder children; also delete `folder.iconFileName` when a folder is removed
- `exportDock` / `importDock` — update `DskmArchive` to hold `[DockItem]` instead of `[AppShortcut]`; include icons from folder children **and** folder custom icons in the icon dictionary

---

## Phase 3 — `FolderButton` — inline dock view

**New file:** `DeskMat/FolderButton.swift`

Renders the folder as a dock item. The icon area has two modes:

- **Custom icon** — if `folder.iconFileName` is set, render it full-size (same as `AppShortcutButton` with `showIconBackground` off).
- **Auto mini-grid** — if no custom icon, show up to 4 mini app icons in a 2×2 grid from the folder's first 4 shortcuts.

```
  Custom icon set        No custom icon
┌──────────────┐      ┌──────────────┐
│              │      │  [A]   [B]  │
│   [icon]     │  or  │  [C]   [D]  │
│              │      │             │
└──────────────┘      └──────────────┘
   Folder Name            Folder Name
```

```swift
struct FolderButton: View {
    let folder: AppFolder
    let isReordering: Bool
    let onRemove: () -> Void
    let onEdit: () -> Void        // opens FolderSheet — Phase 6

    @AppStorage("showLabels") private var showLabels = true
    @State private var showingPopover = false
    @State private var isHovering = false
    @State private var customIcon: Image? = nil

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(isHovering ? 0.15 : 0.08))
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)

                if let icon = customIcon {
                    icon
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    FolderMiniGrid(shortcuts: Array(folder.shortcuts.prefix(4)))
                        .padding(10)
                }
            }
            .frame(width: 64, height: 64)
            .onTapGesture {
                guard !isReordering else { return }
                showingPopover.toggle()
            }
            .onHover { isHovering = $0 }
            .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
                FolderPopover(folder: folder)
            }
            .contextMenu {
                Button("Edit Folder…") { onEdit() }
                Button("Remove Folder", role: .destructive) { onRemove() }
            }

            if showLabels {
                Text(folder.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: 64)
                    .truncationMode(.tail)
            }
        }
        .task(id: folder.iconFileName) {
            guard let fileName = folder.iconFileName else { customIcon = nil; return }
            let url = AppShortcutStore.iconURL(for: fileName)
            customIcon = await Task.detached(priority: .userInitiated) {
                guard let ns = NSImage(contentsOf: url) else { return nil }
                return Image(nsImage: ns)
            }.value
        }
    }
}
```

### `FolderMiniGrid`

A private helper that draws up to 4 mini icons in a 2×2 grid using `LazyVGrid`. Each cell loads its icon image from disk the same way `AppShortcutButton` does, at a smaller render size (~20×20pt). Only rendered when `folder.iconFileName` is nil.

---

## Phase 4 — `FolderPopover` — expanded app grid

**Add to:** `DeskMat/FolderButton.swift` (private struct)

A fixed-width popover with the folder name as a header and a scrollable `LazyVGrid` of app buttons. Each cell behaves like a mini `AppShortcutButton` — tap to launch, no hover animation needed at this scale.

```
┌─────────────────────────┐
│  Dev Tools          ✕  │
├─────────────────────────┤
│  [App] [App] [App]      │
│  [App] [App]            │
└─────────────────────────┘
```

- Header: folder name (left) + close button (right)
- Grid: 3 columns, 64×64 cells with labels
- Tapping an app calls `launchOrFocus()` (extracted from `AppShortcutButton` into a shared helper, or duplicated for now)
- Width: 240pt; max height: 320pt with scroll

```swift
private struct FolderPopover: View {
    let folder: AppFolder

    private let columns = Array(repeating: GridItem(.fixed(64), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(folder.name).font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(folder.shortcuts) { shortcut in
                        FolderAppCell(shortcut: shortcut)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 240)
        .presentationCompactAdaptation(.none)
    }
}
```

`FolderAppCell` is a minimal tap-to-launch cell: icon image + caption label, no complex hover animation.

---

## Phase 5 — `ContentView` wiring

**File:** `DeskMat/ContentView.swift`

This is the most invasive change. Replace `@State private var shortcuts: [AppShortcut]` with `@State private var items: [DockItem]`.

### ForEach branch

```swift
ForEach(items) { item in
    switch item {
    case .shortcut(let shortcut):
        AppShortcutButton(
            shortcut: shortcut,
            onRemove: { removeItem(item) },
            isReordering: draggingID != nil,
            onDragStart: { icon in dragStart(item: item, icon: icon) }
        )
    case .folder(let folder):
        FolderButton(
            folder: folder,
            isReordering: draggingID != nil,
            onRemove: { removeItem(item) }
        )
    }
}
```

### Drag-to-reorder

Currently typed as `AppShortcut?` throughout. Update to `DockItem?`:
- `draggingID: UUID?` — unchanged
- `draggingShortcut: AppShortcut?` → `draggingItem: DockItem?`
- `displayShortcuts: [AppShortcut?]` → `displayItems: [DockItem?]`
- `dragChanged`, `dragEnd` logic unchanged except operating on `[DockItem]`

### Notifications

`shortcutAdded` / `shortcutEdited` still post `AppShortcut` — wrap in `.shortcut(newShortcut)` before appending to `items`. Add a new `folderAdded` notification posting `AppFolder`.

### Persistence

Replace all `AppShortcutStore.save(shortcuts)` calls with `AppShortcutStore.save(items)`.

---

## Phase 6 — Create folder UX

Two entry points:

### 6a — `FolderSheet`

A new sheet view (modelled on `ShortcutSheet`) used for both creating and editing a folder. Fields:

- **Icon** — tappable image well (same pencil-badge pattern as `ShortcutSheet`). Clicking opens `NSOpenPanel` filtered to image types. If no custom icon is chosen the well shows a placeholder grid icon. Clearing the icon reverts to the auto mini-grid.
- **Name** — `TextField` for the folder label.
- Save / Cancel footer.

On save: writes the chosen image to `AppShortcutStore.iconsDirectory` via the existing `copyIcon(from:for:)` helper, sets `folder.iconFileName`, and posts `folderAdded` or `folderEdited` as appropriate. If a previous custom icon existed and a new one was chosen, the old file is deleted via `deleteIcon(named:)`.

### 6b — Context menu "New Folder"

Add "New Folder" to the `ContentView` context menu (alongside "Add Shortcut"). Opens `FolderSheet` in create mode. On save, posts a `folderAdded` notification with the new `AppFolder`. The user then adds apps to it via the folder's own edit flow (Phase 6c).

### 6c — "Edit Folder" context menu item

Right-clicking a `FolderButton` shows "Edit Folder…" which opens `FolderSheet` in edit mode, pre-populated with the existing name and icon.

### 6d — "Add App" inside a folder

Inside `FolderPopover`, add an "Add App" button that opens `ShortcutSheet`. On save, the new `AppShortcut` is appended to the folder's `shortcuts` array and `items` is saved.

### 6e — Remove app from folder

Long-press / right-click an app cell in `FolderPopover` to get a "Remove" context menu item. Updates the folder in `items` and saves.

---

## Migration and backward compatibility

| Concern | Decision |
|---|---|
| Existing `shortcuts.json` (plain `[AppShortcut]`) | Load falls back to legacy decoder, wraps each in `.shortcut()`, resaves in new format |
| Export / import `.dskm` | `DskmArchive` updated; old `.dskm` files (plain `[AppShortcut]`) should still import via the same fallback |
| `AppShortcutStore.deleteIcon` | Must traverse folder children and delete `folder.iconFileName` when a folder is removed |

---

## Acceptance criteria

- Folders with no custom icon appear as a 2×2 mini icon grid with a label.
- Folders with a custom icon show that image full-size, same as an app shortcut.
- Tapping a folder opens a popover grid of its apps; tapping an app launches it.
- Folders can be created from the dock context menu with a name and optional custom icon.
- The custom icon can be changed or cleared via "Edit Folder…".
- When a folder is deleted its custom icon file is also removed from disk.
- Custom folder icons are included in export/import archives.
- Apps can be added to and removed from folders.
- Reordering works for both top-level shortcuts and folders.
- Existing docks load without data loss after the store migration.
- Export / import continues to work.
