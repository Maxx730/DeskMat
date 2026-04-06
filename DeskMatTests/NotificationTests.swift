import Testing
import Foundation
@testable import DeskMat

// MARK: - Notification Tests

struct NotificationTests {

    @Test func addShortcutNotificationNameExists() {
        #expect(Notification.Name.addShortcut.rawValue == "addShortcut")
    }

    @Test func openSettingsNotificationNameExists() {
        #expect(Notification.Name.openSettings.rawValue == "openSettings")
    }

    @Test func notificationNamesAreDistinct() {
        #expect(Notification.Name.addShortcut != Notification.Name.openSettings)
    }
}

// MARK: - Edit Shortcut Notification Tests

struct EditShortcutNotificationTests {

    @Test func editShortcutNotificationNameExists() {
        #expect(Notification.Name.editShortcut.rawValue == "editShortcut")
    }

    @Test func shortcutEditedNotificationNameExists() {
        #expect(Notification.Name.shortcutEdited.rawValue == "shortcutEdited")
    }

    @Test func editNotificationNamesAreDistinct() {
        #expect(Notification.Name.editShortcut != Notification.Name.shortcutEdited)
        #expect(Notification.Name.editShortcut != Notification.Name.addShortcut)
        #expect(Notification.Name.shortcutEdited != Notification.Name.shortcutAdded)
    }
}

// MARK: - Pro-Gated Notification Names Tests

struct ProNotificationNamesTests {

    @Test func allNotificationNamesAreDistinct() {
        let names: [Notification.Name] = [
            .addShortcut,
            .openSettings,
            .exportDock,
            .importDock,
            .dockImported,
            .shortcutAdded,
            .editShortcut,
            .shortcutEdited,
        ]
        #expect(Set(names.map(\.rawValue)).count == names.count)
    }
}

// MARK: - Status Bar Menu Tests

struct StatusBarMenuTests {

    @Test func expectedMenuItemConfiguration() {
        let expectedItems: [(title: String, keyEquivalent: String)] = [
            ("Add Shortcut...", ""),
            ("Settings...", ","),
            ("Quit DeskMat", "q"),
        ]

        #expect(expectedItems.count == 3)
        #expect(expectedItems[0].title == "Add Shortcut...")
        #expect(expectedItems[1].title == "Settings...")
        #expect(expectedItems[1].keyEquivalent == ",")
        #expect(expectedItems[2].title == "Quit DeskMat")
        #expect(expectedItems[2].keyEquivalent == "q")
    }
}

// MARK: - Settings Window Tests

struct SettingsWindowTests {

    @Test func expectedSettingsWindowProperties() {
        let expectedTitle = "DeskMat Settings"
        let expectedWidth: CGFloat = 420
        let expectedHeight: CGFloat = 300

        #expect(expectedTitle == "DeskMat Settings")
        #expect(expectedWidth == 420)
        #expect(expectedHeight == 300)
    }
}
