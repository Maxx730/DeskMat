import Foundation

extension Notification.Name {
    static let addShortcut    = Notification.Name("addShortcut")
    static let openSettings   = Notification.Name("openSettings")
    static let exportDock     = Notification.Name("exportDock")
    static let importDock     = Notification.Name("importDock")
    static let dockImported   = Notification.Name("dockImported")
    static let shortcutAdded  = Notification.Name("shortcutAdded")
    static let editShortcut   = Notification.Name("editShortcut")
    static let shortcutEdited = Notification.Name("shortcutEdited")
    static let addFolder      = Notification.Name("addFolder")
    static let editFolder     = Notification.Name("editFolder")
    static let folderAdded    = Notification.Name("folderAdded")
    static let folderEdited   = Notification.Name("folderEdited")
    static let folderExpansionDismissed = Notification.Name("folderExpansionDismissed")
    #if DEBUG
    static let showOnboarding = Notification.Name("showOnboarding")
    #endif
}
