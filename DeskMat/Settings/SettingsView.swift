import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
import ApplicationServices

struct SettingsView: View {
    @Environment(UpdateService.self) private var updateService

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label(Strings.Settings.general, systemImage: "gearshape") }
            DockSettingsTab()
                .tabItem { Label(Strings.Settings.dock, systemImage: "dock.rectangle") }
            IconsSettingsTab()
                .tabItem { Label("Icons", systemImage: "square.on.square") }
            WidgetsSettingsTab()
                .tabItem { Label(Strings.Settings.widgets, systemImage: "square.grid.2x2") }
            ProUnlockTab()
                .tabItem { Label(Strings.Pro.tabLabel, systemImage: "star.circle") }
            UpdatesSettingsTab(updateService: updateService)
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }
        .padding(20)
        .frame(width: 480)
        .frame(minHeight: 660)
    }
}

@ViewBuilder
private func proLabel(_ title: String, isPro: Bool) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(title)
        if !isPro { ProBadge() }
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("finderDefaultDirectory") private var finderDefaultDirectory = "~/"
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("showWidgetDivider") private var showWidgetDivider = true
    @State private var showingResetConfirmation = false
    #if DEBUG
    @Environment(LicenseManager.self) private var license
    @State private var showingClearCacheConfirmation = false
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


            Section(Strings.Settings.appearance) {
                Picker(Strings.Settings.theme, selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                Toggle(Strings.Settings.showWidgetDivider, isOn: $showWidgetDivider)
            }

            Section {
                Button(Strings.Reset.buttonLabel) {
                    showingResetConfirmation = true
                }
                .foregroundStyle(.red)
                .alert(Strings.Reset.alertTitle, isPresented: $showingResetConfirmation) {
                    Button(Strings.Reset.alertConfirm, role: .destructive) { resetToDefaults() }
                    Button(Strings.Common.cancel, role: .cancel) {}
                } message: {
                    Text(Strings.Reset.alertMessage)
                }
                Text(Strings.Reset.buttonCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            #if DEBUG
            Section("Debug") {
                Toggle("Pro Override", isOn: $debugProOverride)
                Button("Reset Icon Cache") {
                    showingClearCacheConfirmation = true
                }
                .foregroundStyle(.red)
                .alert("Reset Icon Cache?", isPresented: $showingClearCacheConfirmation) {
                    Button("Reset", role: .destructive) { resetIconCache() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will delete all cached icon images. Your dock shortcuts will remain, but icons will reload on next launch.")
                }
                Button("Show Onboarding") {
                    NotificationCenter.default.post(name: .showOnboarding, object: nil)
                }
                Button("Reset App & Quit") {
                    showingResetConfirmation = true
                }
                .foregroundStyle(.red)
                .alert("Reset App?", isPresented: $showingResetConfirmation) {
                    Button("Reset & Quit", role: .destructive) {
                        try? FileManager.default.removeItem(at: AppShortcutStore.storeDirectory)
                        if let bundleID = Bundle.main.bundleIdentifier {
                            UserDefaults.standard.removePersistentDomain(forName: bundleID)
                        }
                        license.resetForDebug()
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

    private func resetToDefaults() {
        let ud = UserDefaults.standard
        // Appearance
        ud.set(AppearanceMode.system.rawValue,  forKey: "appearanceMode")
        ud.set(true,                            forKey: "showLabels")
        ud.set(true,                            forKey: "showWidgetDivider")
        ud.set(DockBackground.system.rawValue,  forKey: "dockBackground")
        ud.set("#000000ff",                     forKey: "dockBackgroundColorHex")
        ud.set(16.0,                            forKey: "dockCornerRadius")
        ud.set(false,                           forKey: "dockStrokeEnabled")
        ud.set("#FFFFFF80",                     forKey: "dockStrokeColorHex")
        ud.set(1.5,                             forKey: "dockStrokeWidth")
        ud.set(VisualEffect.none.rawValue,      forKey: "visualEffect")
        ud.set(ReactiveStyle.none.rawValue,      forKey: "reactiveStyle")
        ud.set(true,                             forKey: "limitReactiveFPS")
        ud.set(0.5,                             forKey: "dockItemShaderIntensity")
        // Dock
        ud.set(DockPosition.bottom.rawValue,    forKey: "dockPosition")
        ud.set(0,                               forKey: "dockOffset")
        ud.set(0,                               forKey: "dockOffsetX")
        ud.set(0,                               forKey: "preferredScreenID")
        ud.set(HoverSize.small.rawValue,        forKey: "hoverSize")
        ud.set(HoverAnimation.bounce.rawValue,  forKey: "hoverAnimation")
        ud.set(false,                           forKey: "autoHideDock")
        ud.set(HideAnimation.fade.rawValue,     forKey: "hideAnimation")
        // Widgets
        ud.set(false,                           forKey: "showWeatherWidget")
        ud.set(false,                           forKey: "showClockWidget")
        ud.set(false,                           forKey: "showImageWidget")
        ud.set(false,                           forKey: "showLEDBoard")
        ud.set(false,                           forKey: "showSystemWidget")
        ud.set(ClockStyle.system.rawValue,      forKey: "clockStyle")
        ud.set(SystemMetric.cpu.rawValue,       forKey: "sysWidgetMetric")
        ud.set("~/Pictures",                    forKey: "imageWidgetDirectory")
        ud.set(37.2707,                         forKey: "weatherLatitude")
        ud.set(-76.7075,                        forKey: "weatherLongitude")
        ud.set(Strings.Weather.defaultLocationName, forKey: "weatherLocationName")
        ud.set("fahrenheit",                        forKey: "weatherTemperatureUnit")
        // General
        ud.set("~/",  forKey: "finderDefaultDirectory")
        // LED Board
        ud.set("",    forKey: LEDBoardWidget.imagePathKey)
        ud.set(80,    forKey: LEDBoardWidget.scrollSpeedKey)
        ud.set(150,   forKey: LEDBoardWidget.frameSpeedKey)
        ud.set(true,  forKey: LEDBoardWidget.widthModeKey)
        // Web Frame
        ud.set(false,                                   forKey: "showWebFrameWidget")
        ud.set("https://example.com",                   forKey: WebFrameSettings.urlKey)
        ud.set(WebFrameRefreshInterval.manual.rawValue, forKey: WebFrameSettings.refreshIntervalKey)
        ud.set(true,                                    forKey: WebFrameSettings.jsEnabledKey)
        ud.set(false,                                   forKey: WebFrameSettings.interactiveModeKey)
        ud.set(false,                                   forKey: WebFrameSettings.persistSessionKey)
    }

    #if DEBUG
    private func resetIconCache() {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: AppShortcutStore.iconsDirectory, includingPropertiesForKeys: nil) {
            files.forEach { try? fm.removeItem(at: $0) }
        }
        AppShortcutStore.save([] as [DockItem])
        AppShortcutStore.initializeWithDefaults()
        let reseeded = AppShortcutStore.load()
        NotificationCenter.default.post(name: .dockImported, object: reseeded)
    }
    #endif
}

// MARK: - Dock

private struct DockSettingsTab: View {
    @Environment(LicenseManager.self) private var license
    @AppStorage("dockPosition") private var dockPosition: DockPosition = .bottom
    @AppStorage("dockOffset") private var dockOffset = 0
    @AppStorage("dockOffsetX") private var dockOffsetX = 0
    @AppStorage("preferredScreenID") private var preferredScreenID: Int = 0
    @AppStorage("autoHideDock") private var autoHideDock = false
    @State private var availableScreens: [NSScreen] = NSScreen.screens
    @AppStorage("hideAnimation") private var hideAnimation: HideAnimation = .fade
    @AppStorage("dockBackground") private var dockBackground: DockBackground = .system
    @AppStorage("dockBackgroundColorHex") private var dockBackgroundColorHex: String = "#000000ff"
    @AppStorage("reactiveStyle") private var reactiveStyle: ReactiveStyle = .none
    @AppStorage("limitReactiveFPS") private var limitReactiveFPS: Bool = true
    @AppStorage("dockCornerRadius") private var dockCornerRadius: Double = 16
    @AppStorage("dockStrokeEnabled") private var dockStrokeEnabled: Bool = false
    @AppStorage("dockStrokeColorHex") private var dockStrokeColorHex: String = "#FFFFFF80"
    @AppStorage("dockStrokeWidth") private var dockStrokeWidth: Double = 1.5

    private var dockBackgroundColor: Color {
        ColorUtils.fromHex(dockBackgroundColorHex)
    }

    private var dockStrokeColor: Color {
        ColorUtils.fromHex(dockStrokeColorHex)
    }

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

                if availableScreens.count > 1 {
                    Picker(Strings.Settings.display, selection: $preferredScreenID) {
                        Text(Strings.Settings.displayMain).tag(0)
                        ForEach(availableScreens, id: \.displayID) { screen in
                            Text(screen.localizedName).tag(Int(screen.displayID ?? 0))
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(
                        for: NSApplication.didChangeScreenParametersNotification)
                    ) { _ in
                        availableScreens = NSScreen.screens
                        if preferredScreenID != 0,
                           !availableScreens.contains(where: { Int($0.displayID ?? 0) == preferredScreenID }) {
                            preferredScreenID = 0
                        }
                    }
                }
            }

            Section {
                HStack(spacing: 8) {
                    Text(Strings.Settings.offsets)
                    Spacer()
                    Text(Strings.Settings.offsetX)
                    TextField("", value: $dockOffsetX, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: $dockOffsetX, step: 1)
                        .labelsHidden()
                    Text(Strings.Settings.offsetY)
                        .padding(.leading, 8)
                    TextField("", value: $dockOffset, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: $dockOffset, step: 1)
                        .labelsHidden()
                }
            }
            
            Section(Strings.Settings.background) {
                Picker(Strings.Settings.dockBackground, selection: $dockBackground) {
                    ForEach(DockBackground.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                if dockBackground == .reactive {
                    Picker(selection: $reactiveStyle) {
                        ForEach(ReactiveStyle.allCases, id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    } label: {
                        proLabel(Strings.Settings.reactiveStyle, isPro: license.isPro)
                    }
                    .disabled(!license.isPro)
                    Toggle(isOn: $limitReactiveFPS) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Limit FPS")
                            Text("Higher frame rates increase power usage.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if dockBackground == .color {
                    ColorPicker(Strings.Settings.dockBackgroundColor, selection: Binding(
                        get: { dockBackgroundColor },
                        set: { newColor in dockBackgroundColorHex = ColorUtils.toHex(newColor) }
                    ))
                    HStack {
                        Text(Strings.Settings.cornerRadius)
                        Spacer()
                        TextField("", value: $dockCornerRadius, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: dockCornerRadius) { _, val in
                                dockCornerRadius = max(0, min(64, val))
                            }
                        Stepper("", value: $dockCornerRadius, in: 0...64, step: 1)
                            .labelsHidden()
                    }
                }
            }

            if dockBackground == .color {
                Section(Strings.Settings.stroke) {
                    Toggle(Strings.Settings.stroke, isOn: $dockStrokeEnabled)
                    if dockStrokeEnabled {
                        ColorPicker(Strings.Settings.strokeColor, selection: Binding(
                            get: { dockStrokeColor },
                            set: { newColor in dockStrokeColorHex = ColorUtils.toHex(newColor) }
                        ))
                        HStack {
                            Text(Strings.Settings.strokeWidth)
                            Spacer()
                            TextField("", value: $dockStrokeWidth, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: dockStrokeWidth) { _, val in
                                    dockStrokeWidth = max(0.5, min(12, val))
                                }
                            Stepper("", value: $dockStrokeWidth, in: 0.5...12, step: 0.5)
                                .labelsHidden()
                        }
                    }
                }
            }

        }
        .formStyle(.grouped)
    }
}

// MARK: - Icons

private struct IconsSettingsTab: View {
    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("showIconBackground") private var showIconBackground = true
    @AppStorage("hoverSize") private var hoverSize: HoverSize = .small
    @AppStorage("hoverAnimation") private var hoverAnimation: HoverAnimation = .bounce

    var body: some View {
        Form {
            Section("General") {
                Toggle(Strings.Settings.showLabels, isOn: $showLabels)
                Toggle(Strings.Settings.showIconBackground, isOn: $showIconBackground)
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
    @Environment(LicenseManager.self)  private var license
    @Environment(EveAuthService.self)  private var eveAuth
    @AppStorage("showWeatherWidget")    private var showWeatherWidget = false
    @AppStorage("showClockWidget")      private var showClockWidget = false
    @AppStorage("showImageWidget")      private var showImageWidget = false
    @AppStorage("showLEDBoard")         private var showLEDBoard = false
    @AppStorage("showSystemWidget")     private var showSystemWidget = false
    @AppStorage("showEveWidget")              private var showEveWidget          = false
    @AppStorage("showWebFrameWidget")         private var showWebFrameWidget     = false
    @AppStorage(WebFrameSettings.urlKey)      private var webFrameURL            = "https://example.com"
    @AppStorage(WebFrameSettings.refreshIntervalKey) private var webFrameRefresh: WebFrameRefreshInterval = .manual
    @AppStorage(WebFrameSettings.jsEnabledKey)       private var webFrameJSEnabled      = true
    @AppStorage(WebFrameSettings.persistSessionKey)  private var webFramePersistSession = false
    #if DEBUG
    @AppStorage("showTestWidget")       private var showTestWidget   = false
    #endif
    @AppStorage("eveWidgetTheme")       private var eveWidgetTheme: EveWidgetTheme = .auto
    @AppStorage("clockStyle")           private var clockStyle: ClockStyle = .system
    @AppStorage("sysWidgetMetric")      private var sysWidgetMetric: SystemMetric = .cpu
    @AppStorage(LEDBoardWidget.imagePathKey)  private var ledBoardImagePath = ""
    @AppStorage(LEDBoardWidget.scrollSpeedKey) private var ledBoardScrollSpeed = 80
    @AppStorage(LEDBoardWidget.frameSpeedKey)  private var ledBoardFrameSpeed = 150
    @AppStorage(LEDBoardWidget.widthModeKey)   private var ledBoardIsWide = true
    @AppStorage("imageWidgetDirectory") private var imageWidgetDirectory = "~/Pictures"
    @AppStorage("weatherLatitude")        private var weatherLatitude     = 37.2707
    @AppStorage("weatherLongitude")       private var weatherLongitude    = -76.7075
    @AppStorage("weatherLocationName")    private var weatherLocationName = Strings.Weather.defaultLocationName
    @AppStorage("weatherTemperatureUnit") private var temperatureUnit     = "fahrenheit"

    @State private var citySearchText  = ""
    @State private var searchResults: [LocationResult] = []
    @State private var isSearching     = false
    @State private var searchTask: Task<Void, Never>? = nil

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $showWeatherWidget) {
                    proLabel(Strings.Settings.showWeatherWidget, isPro: license.isPro)
                }
                .disabled(!license.isPro)
                if showWeatherWidget && license.isPro {
                    HStack {
                        TextField(Strings.Settings.weatherLocationField, text: $citySearchText)
                            .onChange(of: citySearchText) { _, newValue in
                                searchTask?.cancel()
                                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                                guard !trimmed.isEmpty else {
                                    searchResults = []
                                    isSearching = false
                                    return
                                }
                                searchTask = Task {
                                    try? await Task.sleep(for: .milliseconds(350))
                                    guard !Task.isCancelled else { return }
                                    isSearching = true
                                    searchResults = (try? await LocationService.search(trimmed)) ?? []
                                    isSearching = false
                                }
                            }
                        if isSearching {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if !searchResults.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(searchResults.enumerated()), id: \.element.displayName) { index, result in
                                Button {
                                    applyLocation(result)
                                } label: {
                                    HStack {
                                        Text(result.displayName)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 7)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if index < searchResults.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        .background(.background)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.separator, lineWidth: 0.5)
                        }
                    }
                    if searchResults.isEmpty {
                        Text(Strings.Settings.weatherCurrentLocation(weatherLocationName))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(Strings.Settings.temperatureUnit)
                        Spacer()
                        Picker("", selection: $temperatureUnit) {
                            Text("°F").tag("fahrenheit")
                            Text("°C").tag("celsius")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 80)
                        .labelsHidden()
                    }
                }
            }
            Toggle(isOn: $showClockWidget) {
                proLabel(Strings.Settings.showClockWidget, isPro: license.isPro)
            }
            .disabled(!license.isPro)
            if showClockWidget && license.isPro {
                Picker(Strings.Settings.clockStyle, selection: $clockStyle) {
                    ForEach(ClockStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
            }
            Section {
                Toggle(isOn: $showLEDBoard) {
                    proLabel(Strings.Settings.showLEDBoard, isPro: license.isPro)
                }
                .disabled(!license.isPro)
                if license.isPro && showLEDBoard {
                    Text(Strings.Settings.ledBoardPerformanceNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if showLEDBoard && license.isPro {
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
                    proLabel(Strings.Settings.showImageWidget, isPro: license.isPro)
                }
                .disabled(!license.isPro)
                if showImageWidget && license.isPro {
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
            Section {
                Toggle(isOn: $showSystemWidget) {
                    proLabel(Strings.Settings.showSystemWidget, isPro: license.isPro)
                }
                .disabled(!license.isPro)
                if showSystemWidget && license.isPro {
                    Picker(Strings.Settings.sysWidgetMetric, selection: $sysWidgetMetric) {
                        ForEach(SystemMetric.allCases, id: \.self) { metric in
                            Text(metric.rawValue).tag(metric)
                        }
                    }
                }
            }
            Section {
                Toggle(isOn: $showEveWidget) {
                    proLabel(Strings.Eve.settingsLabel, isPro: license.isPro)
                }
                .disabled(!license.isPro)
                if showEveWidget && license.isPro {
                    Picker(Strings.Eve.themeLabel, selection: $eveWidgetTheme) {
                        ForEach(EveWidgetTheme.allCases, id: \.self) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                    if eveAuth.isAuthenticated {
                        HStack(spacing: 10) {
                            AsyncImage(url: URL(string: "https://imageserver.eveonline.com/Character/\(eveAuth.characterId)_64.jpg")) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Circle().fill(.secondary.opacity(0.3))
                            }
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                            Text(eveAuth.characterName)
                                .font(.subheadline)
                            Spacer()
                            Button(Strings.Eve.disconnectButton) {
                                eveAuth.disconnect()
                            }
                            .foregroundStyle(.red)
                        }
                    } else {
                        HStack {
                            Spacer()
                            if eveAuth.isConnecting {
                                ProgressView().controlSize(.small)
                                Text("Connecting...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Button(Strings.Eve.connectButton) {
                                    Task { try? await eveAuth.connect() }
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
            Section {
                Toggle(isOn: $showWebFrameWidget) {
                    proLabel(Strings.WebFrame.settingsLabel, isPro: license.isPro)
                }
                .disabled(!license.isPro)
                if showWebFrameWidget && license.isPro {
                    TextField(Strings.WebFrame.urlField, text: $webFrameURL)
                        .autocorrectionDisabled()
                    Picker(Strings.WebFrame.refreshLabel, selection: $webFrameRefresh) {
                        ForEach(WebFrameRefreshInterval.allCases, id: \.self) { interval in
                            Text(interval.rawValue).tag(interval)
                        }
                    }
                    Toggle(Strings.WebFrame.jsToggle, isOn: $webFrameJSEnabled)
                    Toggle("Keep Session", isOn: $webFramePersistSession)
                    Button(Strings.WebFrame.clearSession, role: .destructive) {
                        WebFrameWidget.clearSession()
                    }
                }
            }
            #if DEBUG
            Section("Debug") {
                Toggle("Test Widget", isOn: $showTestWidget)
            }
            #endif
        }
        .formStyle(.grouped)
    }


    private func applyLocation(_ result: LocationResult) {
        weatherLatitude     = result.latitude
        weatherLongitude    = result.longitude
        weatherLocationName = result.cityName
        citySearchText      = ""
        searchResults       = []
    }
}

// MARK: - Pro Unlock

private struct ProUnlockTab: View {
    @Environment(LicenseManager.self) private var license
    @State private var licenseKeyInput = ""

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    @State private var isActivating = false
    @State private var isDeactivating = false
    @State private var activationResult: ActivationResult? = nil
    @State private var deactivationError: String? = nil

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .padding(.top, 20)

            Text("DeskMat Pro")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Version \(version)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if license.isPro {
                activatedContent
            } else {
                lockedContent
            }

            Text("by Cepholotech LLC")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - Activated State

    @ViewBuilder
    private var activatedContent: some View {
        VStack(spacing: 6) {
            Label(Strings.Pro.activatedHeadline, systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            if let hint = license.licenseKeyHint {
                Text(hint)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            if let validated = license.lastValidated {
                Text(Strings.Pro.lastVerified(validated.formatted(date: .abbreviated, time: .shortened)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(Strings.Pro.offlineBadge)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }

        featureList

        VStack(spacing: 6) {
            if isDeactivating {
                ProgressView(Strings.Pro.deactivatingLabel)
                    .controlSize(.small)
            } else {
                Button(Strings.Pro.deactivateLabel) {
                    Task { await performDeactivate() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.footnote)
            }
            if let error = deactivationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Text(Strings.Pro.deactivateCaption)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Locked State

    @ViewBuilder
    private var lockedContent: some View {
        VStack(spacing: 6) {
            Text(Strings.Pro.lockedHeadline)
                .font(.headline)
            Text(Strings.Pro.lockedSubheadline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }

        featureList

        // Buy CTA
        Button {
            NSWorkspace.shared.open(URL(string: "https://cepholotech.com/deskmat/checkout/")!)
        } label: {
            Text("Buy DeskMat Pro")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

        // License key entry
        VStack(spacing: 8) {
            HStack {
                TextField(Strings.Pro.licenseKeyPlaceholder, text: $licenseKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()

                if isActivating {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 60)
                } else {
                    Button(Strings.Pro.activateLabel) {
                        Task { await performActivate() }
                    }
                    .disabled(licenseKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    .frame(width: 60)
                }
            }

            if let result = activationResult {
                switch result {
                case .success:
                    Label(Strings.Pro.activationSuccess, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .invalid:
                    Text(Strings.Pro.activationInvalid)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                case .alreadyActive:
                    Text(Strings.Pro.activationAlreadyActive)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                case .error(let msg):
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text(Strings.Pro.enterKeyCaption)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Feature List

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Pro.featuresHeader.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach([
                Strings.Pro.featureEffects,
                Strings.Pro.featureReactive,
                Strings.Pro.featureWidgets,
                Strings.Pro.featureExportImport
            ], id: \.self) { label in
                Label(label, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
    }

    // MARK: - Actions

    private func performActivate() async {
        let key = licenseKeyInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        isActivating = true
        activationResult = nil
        activationResult = await license.activate(licenseKey: key)
        if case .success = activationResult { licenseKeyInput = "" }
        isActivating = false
    }

    private func performDeactivate() async {
        isDeactivating = true
        deactivationError = nil
        activationResult = nil
        let result = await license.deactivate()
        if case .error(let msg) = result { deactivationError = msg }
        isDeactivating = false
    }
}

private struct UpdatesSettingsTab: View {
    let updateService: UpdateService

    @State private var lastChecked: Date? = UserDefaults.standard.object(forKey: "lastUpdateCheckDate") as? Date

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 2) {
                Text("DeskMat")
                    .font(.headline)
                Text("Version \(currentVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            statusCard
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            Button {
                Task {
                    await updateService.check(force: true)
                    lastChecked = Date()
                }
            } label: {
                if updateService.isChecking {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Checking...")
                    }
                } else {
                    Text("Check for Updates")
                }
            }
            .disabled(updateService.isChecking)

            if let lastChecked {
                Text("Last checked: \(lastChecked.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
    }

    @ViewBuilder
    private var statusCard: some View {
        if updateService.isUpdateAvailable {
            VStack(alignment: .leading, spacing: 8) {
                Label("DeskMat \(updateService.latestVersion) Available",
                      systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.accent)
                    .font(.subheadline.bold())
                if let notes = updateService.releaseNotes {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                Button("Download") {
                    if let url = updateService.downloadURL {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        } else if !updateService.latestVersion.isEmpty {
            Label("You're up to date. \(updateService.latestVersion) is the latest.",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.subheadline)
        } else {
            Text("No update information yet.")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }
}

