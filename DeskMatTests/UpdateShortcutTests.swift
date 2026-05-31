import Testing
import Foundation
@testable import DeskMat

// MARK: - updateShortcut Folder-Nesting Tests
//
// updateShortcut(_:) is a private method on ContentView and cannot be called
// directly. The two-pass search logic is mirrored here as a standalone function
// that matches the implementation exactly. Any change to that algorithm must
// update this mirror to match.

struct UpdateShortcutTests {

    // Mirrors ContentView.updateShortcut — searches top-level then folder contents.
    // Returns the updated items array (real implementation mutates @State and saves).
    @discardableResult
    private func updateShortcut(_ updated: AppShortcut, in items: [DockItem]) -> [DockItem] {
        var items = items
        if let index = items.firstIndex(where: { $0.id == updated.id }) {
            items[index] = .shortcut(updated)
            return items
        }
        for (i, item) in items.enumerated() {
            if case .folder(var folder) = item,
               let j = folder.shortcuts.firstIndex(where: { $0.id == updated.id }) {
                folder.shortcuts[j] = updated
                items[i] = .folder(folder)
                return items
            }
        }
        return items
    }

    private func makeShortcut(name: String) -> AppShortcut {
        AppShortcut(
            displayName: name,
            bundleIdentifier: "com.test.\(name.lowercased())",
            appURL: URL(filePath: "/Applications/\(name).app"),
            iconFileName: "\(name.lowercased()).png"
        )
    }

    private func makeFolder(name: String, shortcuts: [AppShortcut]) -> AppFolder {
        AppFolder(name: name, shortcuts: shortcuts)
    }

    // MARK: - Top-level updates

    @Test func updatesTopLevelShortcut() {
        let a = makeShortcut(name: "Safari")
        let b = makeShortcut(name: "Mail")
        var modified = a
        modified.customLabel = "Browser"

        let items: [DockItem] = [.shortcut(a), .shortcut(b)]
        let result = updateShortcut(modified, in: items)

        guard case .shortcut(let updated) = result[0] else {
            Issue.record("Expected .shortcut at index 0"); return
        }
        #expect(updated.customLabel == "Browser")
        #expect(updated.id == a.id)
    }

    @Test func updatesCorrectItemAmongMultipleTopLevel() {
        let a = makeShortcut(name: "Safari")
        let b = makeShortcut(name: "Mail")
        let c = makeShortcut(name: "Notes")
        var modified = b
        modified.customLabel = "Inbox"

        let items: [DockItem] = [.shortcut(a), .shortcut(b), .shortcut(c)]
        let result = updateShortcut(modified, in: items)

        guard case .shortcut(let updated) = result[1] else {
            Issue.record("Expected .shortcut at index 1"); return
        }
        #expect(updated.customLabel == "Inbox")
        // Neighbors untouched
        guard case .shortcut(let first) = result[0] else { Issue.record("index 0"); return }
        guard case .shortcut(let third) = result[2] else { Issue.record("index 2"); return }
        #expect(first.customLabel == nil)
        #expect(third.customLabel == nil)
    }

    // MARK: - Folder-nested updates

    @Test func updatesShortcutInsideFolder() {
        let a = makeShortcut(name: "Safari")
        let b = makeShortcut(name: "Mail")
        let folder = makeFolder(name: "Work", shortcuts: [a, b])
        var modified = a
        modified.customLabel = "Browser"

        let items: [DockItem] = [.folder(folder)]
        let result = updateShortcut(modified, in: items)

        guard case .folder(let updatedFolder) = result[0] else {
            Issue.record("Expected .folder at index 0"); return
        }
        #expect(updatedFolder.shortcuts[0].customLabel == "Browser")
        #expect(updatedFolder.shortcuts[0].id == a.id)
    }

    @Test func updatesCorrectShortcutInsideFolder() {
        let a = makeShortcut(name: "Safari")
        let b = makeShortcut(name: "Mail")
        let c = makeShortcut(name: "Notes")
        let folder = makeFolder(name: "Work", shortcuts: [a, b, c])
        var modified = b
        modified.customLabel = "Inbox"

        let items: [DockItem] = [.folder(folder)]
        let result = updateShortcut(modified, in: items)

        guard case .folder(let updatedFolder) = result[0] else {
            Issue.record("Expected .folder at index 0"); return
        }
        #expect(updatedFolder.shortcuts[1].customLabel == "Inbox")
        #expect(updatedFolder.shortcuts[0].customLabel == nil)
        #expect(updatedFolder.shortcuts[2].customLabel == nil)
    }

    @Test func updatesShortcutInSecondFolder() {
        let a = makeShortcut(name: "Safari")
        let b = makeShortcut(name: "Mail")
        let folder1 = makeFolder(name: "Work", shortcuts: [a])
        let folder2 = makeFolder(name: "Personal", shortcuts: [b])
        var modified = b
        modified.customLabel = "Inbox"

        let items: [DockItem] = [.folder(folder1), .folder(folder2)]
        let result = updateShortcut(modified, in: items)

        guard case .folder(let f1) = result[0],
              case .folder(let f2) = result[1] else {
            Issue.record("Expected two folders"); return
        }
        #expect(f1.shortcuts[0].customLabel == nil)
        #expect(f2.shortcuts[0].customLabel == "Inbox")
    }

    // MARK: - Non-mutation of unrelated items

    @Test func doesNotMutateUnrelatedTopLevelShortcut() {
        let a = makeShortcut(name: "Safari")
        let b = makeShortcut(name: "Mail")
        var modified = a
        modified.customLabel = "Browser"

        let items: [DockItem] = [.shortcut(a), .shortcut(b)]
        let result = updateShortcut(modified, in: items)

        guard case .shortcut(let unchanged) = result[1] else {
            Issue.record("Expected .shortcut at index 1"); return
        }
        #expect(unchanged.id == b.id)
        #expect(unchanged.customLabel == nil)
    }

    @Test func doesNotMutateUnrelatedFolder() {
        let a = makeShortcut(name: "Safari")
        let b = makeShortcut(name: "Mail")
        let folder = makeFolder(name: "Work", shortcuts: [b])
        var modified = a
        modified.customLabel = "Browser"

        let items: [DockItem] = [.shortcut(a), .folder(folder)]
        let result = updateShortcut(modified, in: items)

        guard case .folder(let unchangedFolder) = result[1] else {
            Issue.record("Expected .folder at index 1"); return
        }
        #expect(unchangedFolder.shortcuts[0].customLabel == nil)
        #expect(unchangedFolder.shortcuts[0].id == b.id)
    }

    // MARK: - No-op for unknown ID

    @Test func noOpForUnknownID() {
        let a = makeShortcut(name: "Safari")
        let unknown = makeShortcut(name: "Unknown")

        let items: [DockItem] = [.shortcut(a)]
        let result = updateShortcut(unknown, in: items)

        guard case .shortcut(let unchanged) = result[0] else {
            Issue.record("Expected .shortcut at index 0"); return
        }
        #expect(unchanged.id == a.id)
        #expect(unchanged.displayName == "Safari")
    }

    @Test func noOpWhenItemsEmpty() {
        let unknown = makeShortcut(name: "Unknown")
        let result = updateShortcut(unknown, in: [])
        #expect(result.isEmpty)
    }

    // MARK: - Item count preserved

    @Test func itemCountUnchangedAfterTopLevelUpdate() {
        let a = makeShortcut(name: "A")
        let b = makeShortcut(name: "B")
        var modified = a
        modified.customLabel = "Updated"

        let items: [DockItem] = [.shortcut(a), .shortcut(b)]
        let result = updateShortcut(modified, in: items)
        #expect(result.count == 2)
    }

    @Test func itemCountUnchangedAfterFolderUpdate() {
        let a = makeShortcut(name: "A")
        let b = makeShortcut(name: "B")
        let folder = makeFolder(name: "F", shortcuts: [a, b])
        var modified = a
        modified.customLabel = "Updated"

        let items: [DockItem] = [.folder(folder)]
        let result = updateShortcut(modified, in: items)
        #expect(result.count == 1)

        guard case .folder(let updatedFolder) = result[0] else {
            Issue.record("Expected .folder"); return
        }
        #expect(updatedFolder.shortcuts.count == 2)
    }
}
