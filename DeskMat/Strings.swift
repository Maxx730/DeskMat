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
        static let background = "Background"
        static let appearance = "Appearance"
        static let showLabels = "Labels"
        static let showIconBackground = "Icon Background"
        static let showWidgetDivider = "Widget Divider"
        static let dockBackground = "Dock Background"
        static let dockBackgroundColor = "Color"
        static let reactiveStyle = "Reactive Style"
        static let showWeatherWidget = "Weather Widget"
        static let weatherLocationField = "Search city..."
        static let weatherLocationSearch = "Search"
        static let weatherLocationNotFound = "City not found. Try a different name."
        static func weatherCurrentLocation(_ name: String) -> String { "Current location: \(name)" }
        static let showClockWidget = "Clock Widget"
        static let showImageWidget = "Image Widget"
        static let imageWidgetDirectory = "Images Directory"
        static let theme = "Theme"
        static let visualEffect = "Visual Effect"
        static let effectIntensity = "Intensity"
        static let widgets = "Widgets"
        static let hover = "Hover"
        static let scale = "Scale"
        static let animation = "Animation"
        static let dock = "Dock"
        static let position = "Position"
        static let offset = "Offset"
        static let offsets = "Offsets"
        static let offsetX = "X"
        static let offsetY = "Y"
        static let cornerRadius = "Corner Radius"
        static let stroke = "Stroke"
        static let strokeColor = "Color"
        static let strokeWidth = "Width"
        static let pixelUnit = "px"
        static let icons = "Icons"
        static let showLEDBoard = "LED Board"
        static let ledBoardPerformanceNote = "Animating an LED image increases CPU usage while active."
        static let ledBoardImage = "Choose Image..."
        static let ledBoardImageNone = "No image selected"
        static let ledBoardScrollSpeed = "Scroll Speed"
        static let ledBoardFrameSpeed = "Frame Speed"
        static let ledBoardWide = "Wide LED Board"
        static let ledBoardCompact = "Compact"
        static let autoHideDock = "Auto-Hide Dock"
        static let hideAnimation    = "Hide Animation"
        static let showSystemWidget = "System Widget"
        static let sysWidgetMetric  = "Metric"
        static let about = "About"
    }

    // MARK: - Menu

    enum Menu {
        static let addShortcut = "Add Shortcut..."
        static let newFolder = "New Folder..."
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
        static let customLabel = "Label"
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
        static let addFolder = "New Folder"
        static let editFolder = "Edit Folder"
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

    // MARK: - Onboarding

    enum Onboarding {
        static let windowTitle      = "Welcome to DeskMat"
        static let back             = "Back"
        static let skip             = "Skip"
        static let next             = "Next"
        static let getStarted       = "Get Started"

        enum Welcome {
            static let title    = "Welcome to DeskMat"
            static let subtitle = "A customizable dock that lives on your desktop. Let's get it set up the way you like."
        }

        enum Widgets {
            static let title        = "Choose Your Widgets"
            static let subtitle     = "Select which widgets appear alongside your shortcuts."
            static let weather      = "Weather"
            static let clock        = "Clock"
            static let image        = "Image Viewer"
            static let ledBoard     = "LED Board"
        }

        enum Shortcuts {
            static let title          = "Getting Around"
            static let subtitle       = "Here's how to interact with your dock."
            static let iconCaption    = "Right-click any icon to edit or remove it."
            static let menuCaption    = "Click the menu bar icon to add shortcuts and open settings."
        }

        enum Position {
            static let title    = "Dock Position"
            static let subtitle = "Choose where the dock sits on your screen."
            static let bottom   = "Bottom"
            static let top      = "Top"
        }

        enum Appearance {
            static let title          = "Appearance"
            static let subtitle       = "Customize the look of your dock."
            static let theme          = "Theme"
            static let dockBackground = "Dock Background"
        }

        enum Finish {
            static let title    = "You're all set!"
            static let subtitle = "Your dock is ready to go. You can adjust any of these settings later in Preferences."
        }
    }

    // MARK: - Widgets

    enum Widgets {
        static let weather     = "Weather"
        static let clock       = "Clock"
        static let ledBoard    = "LED Board"
        static let images      = "Images"

        enum SystemMonitor {
            static let cpuHeader = "CPU"
            static let ramHeader = "RAM"
            static let netHeader = "NET"
            static let kbPerSec  = "KB/s"
            static let mbPerSec  = "MB/s"
            static func cpuPercent(_ value: Int) -> String { "\(value)%" }
            static func ramUsage(used: Double, total: Double) -> String {
                String(format: "%.1f / %.0f GB", used, total)
            }
        }
    }

    // MARK: - Pro

    enum Pro {
        static let tabLabel            = "Pro"
        static let featuresHeader      = "What's included"
        static let featureEffects      = "Visual Effects"
        static let featureWeather      = "Weather Widget"
        static let featureClock        = "Clock Widget"
        static let featureLED          = "LED Board"
        static let featureImage        = "Image Viewer Widget"
        static let featureSystem       = "System Monitor Widget"
        static let lockedHeadline      = "Unlock the full DeskMat experience"
        static let lockedSubheadline   = "Purchase a license to enable all pro features."
        static let buyLabel            = "Buy DeskMat Pro"
        static let licenseKeyPlaceholder = "License Key"
        static let activateLabel       = "Activate"
        static let activatedHeadline   = "DeskMat Pro is active"
        static let activationSuccess   = "Activated successfully!"
        static let activationInvalid   = "Invalid license key. Please check and try again."
        static let activationAlreadyActive = "This key is already activated on another Mac. Deactivate it there first, or contact support."
        static let enterKeyCaption     = "Already have a license key? Enter it above."
        static let deactivateLabel     = "Deactivate (transfer to another Mac)"
        static let deactivatingLabel   = "Deactivating\u{2026}"
        static let deactivateCaption   = "Deactivating frees up your activation slot so you can use your key on a different machine."
        static func lastVerified(_ date: String) -> String { "Last verified: \(date)" }
        static let offlineBadge        = "Not verified (offline)"
    }

    // MARK: - Reset

    enum Reset {
        static let buttonLabel   = "Reset to Defaults"
        static let alertTitle    = "Reset All Settings?"
        static let alertMessage  = "This will restore all settings to their defaults. Your dock shortcuts and license will not be affected."
        static let alertConfirm  = "Reset"
        static let buttonCaption = "Restores all appearance, dock, and widget settings to their defaults. Shortcuts and your license are not affected."
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
