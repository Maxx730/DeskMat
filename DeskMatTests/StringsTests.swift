import Testing
import Foundation
@testable import DeskMat

// MARK: - Strings Constants Tests

struct StringsConstantsTests {

    @Test func settingsStringsExist() {
        #expect(!Strings.Settings.finderDefaultDirectory.isEmpty)
        #expect(!Strings.Settings.finderDefaultDirectorySublabel.isEmpty)
        #expect(!Strings.Settings.showWeatherWidget.isEmpty)
        #expect(!Strings.Settings.showClockWidget.isEmpty)
    }

    @Test func windowStringsExist() {
        #expect(!Strings.Windows.addShortcut.isEmpty)
        #expect(!Strings.Windows.editShortcut.isEmpty)
        #expect(!Strings.Windows.exportDock.isEmpty)
        #expect(!Strings.Windows.importDock.isEmpty)
        #expect(!Strings.Windows.settings.isEmpty)
    }

    @Test func shortcutStringsExist() {
        #expect(!Strings.Shortcuts.application.isEmpty)
        #expect(!Strings.Shortcuts.icon.isEmpty)
        #expect(!Strings.Shortcuts.customLabel.isEmpty)
        #expect(!Strings.Shortcuts.chooseApp.isEmpty)
        #expect(!Strings.Shortcuts.chooseIcon.isEmpty)
    }

    @Test func weatherStringsExist() {
        #expect(!Strings.Weather.temperaturePlaceholder.isEmpty)
        #expect(!Strings.Weather.defaultLocationName.isEmpty)
    }
}

// MARK: - Additional Strings Constants Tests

struct NewStringsConstantsTests {

    @Test func visualEffectStringsExist() {
        #expect(!Strings.Settings.visualEffect.isEmpty)
        #expect(!Strings.Settings.effectIntensity.isEmpty)
    }

    @Test func notificationStringsExist() {
        #expect(!Strings.Notifications.dockExported.isEmpty)
        #expect(!Strings.Notifications.exportFailed.isEmpty)
        #expect(!Strings.Notifications.dockImported.isEmpty)
        #expect(!Strings.Notifications.importFailed.isEmpty)
    }

    @Test func notificationDynamicStringsWork() {
        let exportBody = Strings.Notifications.dockExportedBody("test.dskm")
        #expect(exportBody.contains("test.dskm"))

        let importBody = Strings.Notifications.dockImportedBody(count: 3, fileName: "dock.dskm")
        #expect(importBody.contains("3"))
        #expect(importBody.contains("dock.dskm"))
    }

    @Test func importSingularPlural() {
        let single = Strings.Notifications.dockImportedBody(count: 1, fileName: "f.dskm")
        #expect(single.contains("shortcut"))
        #expect(!single.contains("shortcuts"))

        let plural = Strings.Notifications.dockImportedBody(count: 2, fileName: "f.dskm")
        #expect(plural.contains("shortcuts"))
    }

    @Test func errorStringsExist() {
        #expect(!Strings.Errors.selectBothAppAndIcon.isEmpty)
        #expect(!Strings.Errors.selectAnApp.isEmpty)
        #expect(!Strings.Errors.failedToCreateArchive.isEmpty)
        #expect(!Strings.Errors.failedToExtractArchive.isEmpty)
        #expect(!Strings.Errors.invalidDskmFile.isEmpty)
    }

    @Test func errorDynamicStringWorks() {
        let msg = Strings.Errors.failedToSaveIcon("disk full")
        #expect(msg.contains("disk full"))
    }
}

// MARK: - Onboarding Strings Tests

struct OnboardingStringsTests {

    @Test func navigationStringsExistAndAreNonEmpty() {
        #expect(!Strings.Onboarding.windowTitle.isEmpty)
        #expect(!Strings.Onboarding.back.isEmpty)
        #expect(!Strings.Onboarding.skip.isEmpty)
        #expect(!Strings.Onboarding.next.isEmpty)
        #expect(!Strings.Onboarding.getStarted.isEmpty)
    }

    @Test func welcomeStepStringsExist() {
        #expect(!Strings.Onboarding.Welcome.title.isEmpty)
        #expect(!Strings.Onboarding.Welcome.subtitle.isEmpty)
    }

    @Test func widgetsStepStringsExist() {
        #expect(!Strings.Onboarding.Widgets.title.isEmpty)
        #expect(!Strings.Onboarding.Widgets.subtitle.isEmpty)
        #expect(!Strings.Onboarding.Widgets.weather.isEmpty)
        #expect(!Strings.Onboarding.Widgets.clock.isEmpty)
        #expect(!Strings.Onboarding.Widgets.image.isEmpty)
        #expect(!Strings.Onboarding.Widgets.ledBoard.isEmpty)
    }

    @Test func positionStepStringsExist() {
        #expect(!Strings.Onboarding.Position.title.isEmpty)
        #expect(!Strings.Onboarding.Position.subtitle.isEmpty)
        #expect(!Strings.Onboarding.Position.bottom.isEmpty)
        #expect(!Strings.Onboarding.Position.top.isEmpty)
    }

    @Test func appearanceStepStringsExist() {
        #expect(!Strings.Onboarding.Appearance.title.isEmpty)
        #expect(!Strings.Onboarding.Appearance.subtitle.isEmpty)
        #expect(!Strings.Onboarding.Appearance.theme.isEmpty)
        #expect(!Strings.Onboarding.Appearance.dockBackground.isEmpty)
    }

    @Test func finishStepStringsExist() {
        #expect(!Strings.Onboarding.Finish.title.isEmpty)
        #expect(!Strings.Onboarding.Finish.subtitle.isEmpty)
    }

    @Test func navigationStringsAreDistinct() {
        let labels = [
            Strings.Onboarding.back,
            Strings.Onboarding.skip,
            Strings.Onboarding.next,
            Strings.Onboarding.getStarted,
        ]
        #expect(Set(labels).count == labels.count)
    }

    @Test func positionLabelsMatchDockPositionRawValues() {
        #expect(Strings.Onboarding.Position.bottom == DockPosition.bottom.rawValue)
        #expect(Strings.Onboarding.Position.top == DockPosition.top.rawValue)
    }
}

// MARK: - HideAnimation & System Widget Strings Tests

struct HideAnimationAndSystemWidgetStringsTests {

    @Test func hideAnimationStringExists() {
        #expect(!Strings.Settings.hideAnimation.isEmpty)
    }

    @Test func showSystemWidgetStringExists() {
        #expect(!Strings.Settings.showSystemWidget.isEmpty)
    }

    @Test func sysWidgetMetricStringExists() {
        #expect(!Strings.Settings.sysWidgetMetric.isEmpty)
    }

    @Test func allNewSettingStringsAreDistinct() {
        let strings = [
            Strings.Settings.hideAnimation,
            Strings.Settings.showSystemWidget,
            Strings.Settings.sysWidgetMetric,
        ]
        #expect(Set(strings).count == strings.count)
    }
}
