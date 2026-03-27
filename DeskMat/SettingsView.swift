import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label(Strings.Settings.general, systemImage: "gearshape") }
            AppearanceSettingsTab()
                .tabItem { Label(Strings.Settings.appearance, systemImage: "paintbrush") }
            DockSettingsTab()
                .tabItem { Label(Strings.Settings.dock, systemImage: "dock.rectangle") }
            WidgetsSettingsTab()
                .tabItem { Label(Strings.Settings.widgets, systemImage: "square.grid.2x2") }
            AboutSettingsTab()
                .tabItem { Label(Strings.Settings.about, systemImage: "info.circle") }
        }
        .padding(20)
        .frame(width: 380)
        .frame(minHeight: 420)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("finderDefaultDirectory") private var finderDefaultDirectory = "~/"

    var body: some View {
        Form {
            Toggle(Strings.Settings.launchAtLogin, isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                TextField(Strings.Settings.finderDefaultDirectory, text: $finderDefaultDirectory)
                Text(Strings.Settings.finderDefaultDirectorySublabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

private struct AppearanceSettingsTab: View {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("showDockBackground") private var showDockBackground = true
    @AppStorage("dockBackgroundColorHex") private var dockBackgroundColorHex: String = "#000000ff"
    @AppStorage("visualEffect") private var visualEffect: VisualEffect = .none
    @AppStorage("dockItemShaderIntensity") private var dockItemShaderIntensity = 0.5

    private var dockBackgroundColor: Color {
        ColorUtils.fromHex(dockBackgroundColorHex)
    }

    var body: some View {
        Form {
            Picker(Strings.Settings.theme, selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Toggle(Strings.Settings.showLabels, isOn: $showLabels)

            Toggle(Strings.Settings.showDockBackground, isOn: $showDockBackground)

            ColorPicker(Strings.Settings.dockBackgroundColor, selection: Binding(
                get: { dockBackgroundColor },
                set: { newColor in
                    dockBackgroundColorHex = ColorUtils.toHex(newColor)
                }
            ))

            Picker(Strings.Settings.visualEffect, selection: $visualEffect) {
                ForEach(VisualEffect.allCases, id: \.self) { effect in
                    Text(effect.rawValue).tag(effect)
                }
            }

            if visualEffect != .none {
                Slider(value: $dockItemShaderIntensity, in: 0.0...1.0) {
                    Text(Strings.Settings.effectIntensity)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Dock

private struct DockSettingsTab: View {
    @AppStorage("dockPosition") private var dockPosition: DockPosition = .bottom
    @AppStorage("dockOffset") private var dockOffset = 0
    @AppStorage("hoverSize") private var hoverSize: HoverSize = .small
    @AppStorage("hoverAnimation") private var hoverAnimation: HoverAnimation = .bounce

    var body: some View {
        Form {
            Section(Strings.Settings.dock) {
                Picker(Strings.Settings.position, selection: $dockPosition) {
                    ForEach(DockPosition.allCases, id: \.self) { position in
                        Text(position.rawValue).tag(position)
                    }
                }

                HStack {
                    Text(Strings.Settings.offset)
                    Spacer()
                    TextField("", value: $dockOffset, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Text(Strings.Settings.pixelUnit)
                        .foregroundStyle(.secondary)
                }
            }

            Section(Strings.Settings.hover) {
                Picker(Strings.Settings.scale, selection: $hoverSize) {
                    ForEach(HoverSize.allCases, id: \.self) { size in
                        Text(size.rawValue).tag(size)
                    }
                }

                Picker(Strings.Settings.animation, selection: $hoverAnimation) {
                    ForEach(HoverAnimation.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Widgets

private struct WidgetsSettingsTab: View {
    @AppStorage("showWeatherWidget") private var showWeatherWidget = true
    @AppStorage("showClockWidget") private var showClockWidget = true
    @AppStorage("showImageWidget") private var showImageWidget = true
    @AppStorage("imageWidgetDirectory") private var imageWidgetDirectory = "~/Pictures"
    var body: some View {
        Form {
            Toggle(Strings.Settings.showWeatherWidget, isOn: $showWeatherWidget)
            Toggle(Strings.Settings.showClockWidget, isOn: $showClockWidget)
            Section {
                Toggle(Strings.Settings.showImageWidget, isOn: $showImageWidget)
                if showImageWidget {
                    HStack {
                        Text(imageWidgetDirectory)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(Strings.Settings.imageWidgetDirectory) {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.prompt = "Choose"
                            if panel.runModal() == .OK, let url = panel.url {
                                imageWidgetDirectory = url.path(percentEncoded: false)
                                ImageUtils.saveBookmark(for: url, bookmarkKey: ImageWidget.bookmarkKey)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutSettingsTab: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
            Text("DeskMat")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Version \(version) (\(build))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("by John Kinghorn")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
