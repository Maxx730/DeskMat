import Foundation

/// Centralized user-facing strings for easy modification.
enum Strings {

    // MARK: - Common

    enum Common {
        static let cancel = "Cancel"
        static let save = "Save"
    }

    // MARK: - Settings

    enum Settings {
        static let general = "General"
        static let launchAtLogin = "Launch at Login"
        static let finderDefaultDirectory = "Default Directory"
        static let finderDefaultDirectorySublabel = "Only applies to Finder"
        static let appearance = "Appearance"
        static let showLabels = "Show Labels"
        static let showWeatherWidget = "Show Weather Widget"
        static let showClockWidget = "Show Clock Widget"
        static let showBatteryWidget = "Show Battery Widget"
        static let showBatteryPercentage = "Show Battery Percentage"
        static let visualEffect = "Visual Effect"
        static let effectIntensity = "Intensity"
        static let widgets = "Widgets"
        static let hover = "Hover"
        static let scale = "Scale"
        static let animation = "Animation"
        static let dock = "Dock"
        static let position = "Position"
        static let offset = "Offset"
        static let pixelUnit = "px"
        static let icons = "Icons"
        static let borderEffect = "Border Effect"
    }

    // MARK: - Menu

    enum Menu {
        static let addShortcut = "Add Shortcut..."
        static let exportDock = "Export Dock..."
        static let importDock = "Import Dock..."
        static let settings = "Settings..."
        static let toggleDock = "Toggle Dock"
        static let quitDeskMat = "Quit DeskMat"
        static let edit = "Edit..."
        static let remove = "Remove"
    }

    // MARK: - Shortcuts

    enum Shortcuts {
        static let application = "Application"
        static let icon = "Icon"
        static let customLabel = "Custom Label"
        static let chooseApp = "Choose App..."
        static let chooseIcon = "Choose Icon..."
        static let noAppSelected = "No app selected"
        static let add = "Add"
        static let addAppShortcut = "Add App Shortcut"
        static let editAppShortcut = "Edit App Shortcut"
        static let selectAnApplication = "Select an Application"
        static let selectACustomIconImage = "Select a Custom Icon Image"
    }

    // MARK: - Weather

    enum Weather {
        static let temperaturePlaceholder = "--°"
        static let defaultLocationName = "Williamsburg, VA"
    }

    // MARK: - Windows

    enum Windows {
        static let addShortcut = "Add Shortcut"
        static let editShortcut = "Edit Shortcut"
        static let exportDock = "Export Dock"
        static let importDock = "Import Dock"
        static let settings = "DeskMat Settings"
    }

    // MARK: - Notifications

    enum Notifications {
        static let dockExported = "Dock Exported"
        static let exportFailed = "Export Failed"
        static let dockImported = "Dock Imported"
        static let importFailed = "Import Failed"

        static func dockExportedBody(_ fileName: String) -> String {
            "Your dock was exported to \(fileName)."
        }

        static func dockImportedBody(count: Int, fileName: String) -> String {
            "Imported \(count) shortcut\(count == 1 ? "" : "s") from \(fileName)."
        }
    }

    // MARK: - Defaults

    enum Defaults {
        static let exportFileName = "MyDock.dskm"
    }

    // MARK: - Errors

    enum Errors {
        static let selectBothAppAndIcon = "Please select both an app and an icon image."
        static let selectAnApp = "Please select an app."
        static let failedToCreateArchive = "Failed to create .dskm archive"
        static let failedToExtractArchive = "Failed to extract .dskm archive"
        static let invalidDskmFile = "Invalid .dskm file: missing shortcuts.json"

        static func failedToSaveIcon(_ description: String) -> String {
            "Failed to save icon: \(description)"
        }
    }
}
