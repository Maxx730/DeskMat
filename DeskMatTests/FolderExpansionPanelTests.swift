import Testing
import AppKit
import SwiftUI
@testable import DeskMat

// MARK: - FolderExpansionPanel Background Config Passthrough Tests
//
// FolderExpansionPanel.show() takes five background-config parameters and must
// pass each one unchanged to the FolderExpansionView it creates. Because the
// panel is an NSPanel singleton, the values are verified via:
//
//   panel.contentView as? FirstMouseHostingView<FolderExpansionView>
//
// contentView is set synchronously inside show() before any animation starts,
// so the cast succeeds immediately after show() returns.
//
// @MainActor + @Suite(.serialized) guard the shared singleton against races
// with itself across test runs.

@MainActor
@Suite(.serialized)
struct FolderExpansionPanelTests {

    private var panel: FolderExpansionPanel { .shared }

    private func makeFolder(shortcuts: [AppShortcut] = []) -> AppFolder {
        AppFolder(name: "TestFolder", shortcuts: shortcuts)
    }

    // Call show() with default values for everything except the one under test.
    // dockTopY = -2000 keeps the panel well off-screen during tests.
    private func showPanel(
        folder: AppFolder? = nil,
        dockBackground: DockBackground = .system,
        colorHex: String = "#000000ff",
        cornerRadius: Double = 16
    ) {
        panel.show(
            folder: folder ?? makeFolder(),
            centeredAt: 0,
            dockTopY: -2000,
            windowState: WindowStateService(),
            entitlements: LicenseManager(),
            dockBackground: dockBackground,
            dockBackgroundColorHex: colorHex,
            dockCornerRadius: cornerRadius
        )
    }

    // Access the FolderExpansionView stored in the panel's content view.
    private var rootView: FolderExpansionView? {
        (panel.contentView as? FirstMouseHostingView<FolderExpansionView>)?.rootView
    }

    // MARK: - dockBackground passthrough

    @Test func showPassesColorBackgroundToView() {
        showPanel(dockBackground: .color)
        #expect(rootView?.dockBackground == .color)
    }

    @Test func showPassesTransparentBackgroundToView() {
        showPanel(dockBackground: .transparent)
        #expect(rootView?.dockBackground == .transparent)
    }

    @Test func showPassesReactiveBackgroundToView() {
        showPanel(dockBackground: .reactive)
        #expect(rootView?.dockBackground == .reactive)
    }

    @Test func showPassesSystemBackgroundToView() {
        showPanel(dockBackground: .system)
        #expect(rootView?.dockBackground == .system)
    }

    @Test func showOverwritesPreviousBackground() {
        showPanel(dockBackground: .color)
        #expect(rootView?.dockBackground == .color)
        showPanel(dockBackground: .transparent)
        #expect(rootView?.dockBackground == .transparent)
    }

    // MARK: - dockBackgroundColorHex passthrough

    @Test func showPassesColorHexToView() {
        showPanel(colorHex: "#FF0000ff")
        #expect(rootView?.dockBackgroundColorHex == "#FF0000ff")
    }

    @Test func showPassesBlackHexToView() {
        showPanel(colorHex: "#000000ff")
        #expect(rootView?.dockBackgroundColorHex == "#000000ff")
    }

    @Test func showPassesArbitraryHexToView() {
        showPanel(colorHex: "#1A2B3Cff")
        #expect(rootView?.dockBackgroundColorHex == "#1A2B3Cff")
    }

    // MARK: - dockCornerRadius passthrough

    @Test func showPassesCornerRadiusToView() {
        showPanel(cornerRadius: 24)
        #expect(rootView?.dockCornerRadius == 24)
    }

    @Test func showPassesZeroCornerRadiusToView() {
        showPanel(cornerRadius: 0)
        #expect(rootView?.dockCornerRadius == 0)
    }

    @Test func showPassesLargeCornerRadiusToView() {
        showPanel(cornerRadius: 40)
        #expect(rootView?.dockCornerRadius == 40)
    }

    // MARK: - All parameters in one call

    @Test func showPassesAllParametersSimultaneously() {
        showPanel(
            dockBackground: .color,
            colorHex: "#AABBCCDD",
            cornerRadius: 20
        )
        #expect(rootView?.dockBackground        == .color)
        #expect(rootView?.dockBackgroundColorHex == "#AABBCCDD")
        #expect(rootView?.dockCornerRadius       == 20)
    }

    // MARK: - openFolderID passthrough

    @Test func showSetsOpenFolderID() {
        let folder = makeFolder()
        showPanel(folder: folder)
        #expect(panel.openFolderID == folder.id)
    }

    @Test func showOverwritesPreviousFolderID() {
        let folder1 = makeFolder()
        let folder2 = makeFolder()
        showPanel(folder: folder1)
        showPanel(folder: folder2)
        #expect(panel.openFolderID == folder2.id)
        #expect(panel.openFolderID != folder1.id)
    }

    // MARK: - Content view is a FirstMouseHostingView after show

    @Test func contentViewIsFirstMouseHostingViewAfterShow() {
        showPanel()
        #expect(panel.contentView is FirstMouseHostingView<FolderExpansionView>)
    }
}
