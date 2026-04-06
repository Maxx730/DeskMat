import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

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
        .frame(width: 480)
        .frame(minHeight: 420)
    }
}

@ViewBuilder
private func proLabel(_ title: String, isPro: Bool) -> some View {
    HStack(spacing: 6) {
        Text(title)
        if !isPro { ProBadge() }
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("finderDefaultDirectory") private var finderDefaultDirectory = "~/"
    #if DEBUG
    @State private var showingResetConfirmation = false
    @AppStorage("debugProOverride") private var debugProOverride = false
    #endif

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

            #if DEBUG
            Section("Debug") {
                Toggle("Pro Override", isOn: $debugProOverride)
                Button("Reset App & Quit") {
                    showingResetConfirmation = true
                }
                .foregroundStyle(.red)
                .alert("Reset App?", isPresented: $showingResetConfirmation) {
                    Button("Reset & Quit", role: .destructive) {
                        try? FileManager.default.removeItem(at: AppShortcutStore.storeDirectory)
                        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
                        UserDefaults.standard.removeObject(forKey: "debugProOverride")
                        NSApp.terminate(nil)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will delete all shortcuts, icons, and reset onboarding. The app will quit immediately.")
                }
            }
            #endif
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

private struct AppearanceSettingsTab: View {
    @Environment(EntitlementManager.self) private var entitlements
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("showWidgetDivider") private var showWidgetDivider = true
    @AppStorage("dockBackground") private var dockBackground: DockBackground = .system
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
            Toggle(Strings.Settings.showWidgetDivider, isOn: $showWidgetDivider)

            Picker(Strings.Settings.dockBackground, selection: $dockBackground) {
                ForEach(DockBackground.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }

            if dockBackground == .color {
                ColorPicker(Strings.Settings.dockBackgroundColor, selection: Binding(
                    get: { dockBackgroundColor },
                    set: { newColor in dockBackgroundColorHex = ColorUtils.toHex(newColor) }
                ))
            }

            Picker(selection: $visualEffect) {
                ForEach(VisualEffect.allCases, id: \.self) { effect in
                    Text(effect.rawValue).tag(effect)
                }
            } label: {
                proLabel(Strings.Settings.visualEffect, isPro: entitlements.isPro)
            }
            .disabled(!entitlements.isPro)

            if visualEffect != .none && entitlements.isPro {
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
    @AppStorage("autoHideDock") private var autoHideDock = false
    @AppStorage("hideAnimation") private var hideAnimation: HideAnimation = .fade

    var body: some View {
        Form {
            Section(Strings.Settings.dock) {
                Toggle(Strings.Settings.autoHideDock, isOn: $autoHideDock)

                if autoHideDock {
                    Picker(Strings.Settings.hideAnimation, selection: $hideAnimation) {
                        ForEach(HideAnimation.allCases, id: \.self) { anim in
                            Text(anim.rawValue).tag(anim)
                        }
                    }
                }

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
    @Environment(EntitlementManager.self) private var entitlements
    @AppStorage("showWeatherWidget")    private var showWeatherWidget = true
    @AppStorage("showClockWidget")      private var showClockWidget = true
    @AppStorage("showImageWidget")      private var showImageWidget = true
    @AppStorage("showLEDBoard")         private var showLEDBoard = true
    @AppStorage("showSystemWidget")     private var showSystemWidget = true
    @AppStorage("sysWidgetMetric")      private var sysWidgetMetric: SystemMetric = .cpu
    @AppStorage(LEDBoardWidget.imagePathKey)  private var ledBoardImagePath = ""
    @AppStorage(LEDBoardWidget.scrollSpeedKey) private var ledBoardScrollSpeed = 80
    @AppStorage(LEDBoardWidget.frameSpeedKey)  private var ledBoardFrameSpeed = 150
    @AppStorage(LEDBoardWidget.widthModeKey)   private var ledBoardIsWide = true
    @AppStorage("imageWidgetDirectory") private var imageWidgetDirectory = "~/Pictures"
    @AppStorage("weatherLatitude")      private var weatherLatitude     = 37.2707
    @AppStorage("weatherLongitude")     private var weatherLongitude    = -76.7075
    @AppStorage("weatherLocationName")  private var weatherLocationName = Strings.Weather.defaultLocationName

    @State private var citySearchText = ""
    @State private var isGeocoding    = false
    @State private var geocodeError   = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $showWeatherWidget) {
                    proLabel(Strings.Settings.showWeatherWidget, isPro: entitlements.isPro)
                }
                .disabled(!entitlements.isPro)
                if showWeatherWidget && entitlements.isPro {
                    HStack {
                        TextField(Strings.Settings.weatherLocationField, text: $citySearchText)
                            .onSubmit { Task { await performGeocode() } }
                        if isGeocoding {
                            ProgressView().controlSize(.small)
                        } else {
                            Button(Strings.Settings.weatherLocationSearch) {
                                Task { await performGeocode() }
                            }
                            .disabled(citySearchText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    if geocodeError {
                        Text(Strings.Settings.weatherLocationNotFound)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Text(Strings.Settings.weatherCurrentLocation(weatherLocationName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $showClockWidget) {
                proLabel(Strings.Settings.showClockWidget, isPro: entitlements.isPro)
            }
            .disabled(!entitlements.isPro)
            Section {
                Toggle(isOn: $showLEDBoard) {
                    proLabel(Strings.Settings.showLEDBoard, isPro: entitlements.isPro)
                }
                .disabled(!entitlements.isPro)
                if showLEDBoard && entitlements.isPro {
                    HStack {
                        Text(ledBoardImagePath.isEmpty ? Strings.Settings.ledBoardImageNone : URL(fileURLWithPath: ledBoardImagePath).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(Strings.Settings.ledBoardImage) {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = true
                            panel.canChooseDirectories = false
                            panel.allowsMultipleSelection = false
                            panel.allowedContentTypes = [.image]
                            panel.prompt = "Choose"
                            if panel.runModal() == .OK, let url = panel.url {
                                ledBoardImagePath = url.path(percentEncoded: false)
                                ImageUtils.saveBookmark(for: url, bookmarkKey: LEDBoardWidget.bookmarkKey)
                            }
                        }
                    }
                    Toggle(Strings.Settings.ledBoardWide, isOn: $ledBoardIsWide)
                    Slider(
                        value: Binding(
                            get: { -Double(ledBoardScrollSpeed) },
                            set: { ledBoardScrollSpeed = max(20, min(500, Int(-$0))) }
                        ),
                        in: -500...(-20)
                    ) {
                        Text(Strings.Settings.ledBoardScrollSpeed)
                    }
                    Slider(
                        value: Binding(
                            get: { -Double(ledBoardFrameSpeed) },
                            set: { ledBoardFrameSpeed = max(50, min(1000, Int(-$0))) }
                        ),
                        in: -1000...(-50)
                    ) {
                        Text(Strings.Settings.ledBoardFrameSpeed)
                    }
                }
            }
            Section {
                Toggle(isOn: $showImageWidget) {
                    proLabel(Strings.Settings.showImageWidget, isPro: entitlements.isPro)
                }
                .disabled(!entitlements.isPro)
                if showImageWidget && entitlements.isPro {
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

    private func performGeocode() async {
        let query = citySearchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isGeocoding = true
        geocodeError = false
        do {
            let result = try await LocationService.geocode(query)
            weatherLatitude     = result.latitude
            weatherLongitude    = result.longitude
            weatherLocationName = result.displayName
            citySearchText      = ""
        } catch {
            geocodeError = true
        }
        isGeocoding = false
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
