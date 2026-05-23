import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
import ApplicationServices

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label(Strings.Settings.general, systemImage: "gearshape") }
            AppearanceSettingsTab()
                .tabItem { Label(Strings.Settings.appearance, systemImage: "paintbrush") }
            DockSettingsTab()
                .tabItem { Label(Strings.Settings.dock, systemImage: "dock.rectangle") }
            IconsSettingsTab()
                .tabItem { Label("Icons", systemImage: "square.on.square") }
            WidgetsSettingsTab()
                .tabItem { Label(Strings.Settings.widgets, systemImage: "square.grid.2x2") }
            ProUnlockTab()
                .tabItem { Label(Strings.Pro.tabLabel, systemImage: "star.circle") }
            AboutSettingsTab()
                .tabItem { Label(Strings.Settings.about, systemImage: "info.circle") }
        }
        .padding(20)
        .frame(width: 480)
        .frame(minHeight: 560)
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
    @AppStorage("advancedWindowManagement") private var advancedWindowManagement = false
    @State private var isAccessibilityTrusted = AXIsProcessTrusted()
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

            Section("Advanced") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(Strings.Settings.advancedWindowManagement, isOn: $advancedWindowManagement)
                        .onChange(of: advancedWindowManagement) { _, enabled in
                            isAccessibilityTrusted = AXIsProcessTrusted()
                            if enabled && !isAccessibilityTrusted {
                                NSWorkspace.shared.open(
                                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                                )
                            }
                        }
                    Group {
                        if isAccessibilityTrusted {
                            Text(Strings.Settings.accessibilityGranted)
                                .foregroundStyle(.green)
                        } else if advancedWindowManagement {
                            Text("Accessibility permission not granted. Enable it in ") +
                            Text("System Settings > Privacy & Security > Accessibility").bold() +
                            Text(".")
                        } else {
                            Text(Strings.Settings.advancedWindowManagementSublabel)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 52)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    isAccessibilityTrusted = AXIsProcessTrusted()
                }

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
        ud.set(VisualEffect.none.rawValue,      forKey: "visualEffect")
        ud.set(ReactiveStyle.none.rawValue,      forKey: "reactiveStyle")
        ud.set(0.5,                             forKey: "dockItemShaderIntensity")
        // Dock
        ud.set(DockPosition.bottom.rawValue,    forKey: "dockPosition")
        ud.set(0,                               forKey: "dockOffset")
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
        ud.set(SystemMetric.cpu.rawValue,       forKey: "sysWidgetMetric")
        ud.set(false,                           forKey: "showStockWidget")
        ud.set("AAPL,MSFT,GOOGL",              forKey: "stockTickerSymbols")
        ud.set("~/Pictures",                    forKey: "imageWidgetDirectory")
        ud.set(37.2707,                         forKey: "weatherLatitude")
        ud.set(-76.7075,                        forKey: "weatherLongitude")
        ud.set(Strings.Weather.defaultLocationName, forKey: "weatherLocationName")
        // General
        ud.set("~/",  forKey: "finderDefaultDirectory")
        ud.set(false, forKey: "advancedWindowManagement")
        // LED Board
        ud.set("",    forKey: LEDBoardWidget.imagePathKey)
        ud.set(80,    forKey: LEDBoardWidget.scrollSpeedKey)
        ud.set(150,   forKey: LEDBoardWidget.frameSpeedKey)
        ud.set(true,  forKey: LEDBoardWidget.widthModeKey)
    }

    #if DEBUG
    private func resetIconCache() {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: AppShortcutStore.iconsDirectory, includingPropertiesForKeys: nil) {
            files.forEach { try? fm.removeItem(at: $0) }
        }
        AppShortcutStore.save([])
        AppShortcutStore.initializeWithDefaults()
        let reseeded = AppShortcutStore.load()
        NotificationCenter.default.post(name: .dockImported, object: reseeded)
    }
    #endif
}

// MARK: - Appearance

private struct AppearanceSettingsTab: View {
    @Environment(LicenseManager.self) private var license
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("showWidgetDivider") private var showWidgetDivider = true

    var body: some View {
        Form {
            Section("General") {
                Picker(Strings.Settings.theme, selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                Toggle(Strings.Settings.showWidgetDivider, isOn: $showWidgetDivider)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Dock

private struct DockSettingsTab: View {
    @Environment(LicenseManager.self) private var license
    @AppStorage("dockPosition") private var dockPosition: DockPosition = .bottom
    @AppStorage("dockOffset") private var dockOffset = 0
    @AppStorage("autoHideDock") private var autoHideDock = false
    @AppStorage("hideAnimation") private var hideAnimation: HideAnimation = .fade
    @AppStorage("dockBackground") private var dockBackground: DockBackground = .system
    @AppStorage("dockBackgroundColorHex") private var dockBackgroundColorHex: String = "#000000ff"
    @AppStorage("reactiveStyle") private var reactiveStyle: ReactiveStyle = .none
    @AppStorage("dockCornerRadius") private var dockCornerRadius: Double = 16

    private var dockBackgroundColor: Color {
        ColorUtils.fromHex(dockBackgroundColorHex)
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
    @Environment(LicenseManager.self) private var license
    @AppStorage("showWeatherWidget")    private var showWeatherWidget = false
    @AppStorage("showClockWidget")      private var showClockWidget = false
    @AppStorage("showImageWidget")      private var showImageWidget = false
    @AppStorage("showLEDBoard")         private var showLEDBoard = false
    @AppStorage("showSystemWidget")     private var showSystemWidget = false
    @AppStorage("sysWidgetMetric")      private var sysWidgetMetric: SystemMetric = .cpu
    @AppStorage("showStockWidget")      private var showStockWidget = false
    @AppStorage("stockTickerSymbols")   private var stockTickerSymbols = "AAPL,MSFT,GOOGL"
    @AppStorage(LEDBoardWidget.imagePathKey)  private var ledBoardImagePath = ""
    @AppStorage(LEDBoardWidget.scrollSpeedKey) private var ledBoardScrollSpeed = 80
    @AppStorage(LEDBoardWidget.frameSpeedKey)  private var ledBoardFrameSpeed = 150
    @AppStorage(LEDBoardWidget.widthModeKey)   private var ledBoardIsWide = true
    @AppStorage("imageWidgetDirectory") private var imageWidgetDirectory = "~/Pictures"
    @AppStorage("weatherLatitude")      private var weatherLatitude     = 37.2707
    @AppStorage("weatherLongitude")     private var weatherLongitude    = -76.7075
    @AppStorage("weatherLocationName")  private var weatherLocationName = Strings.Weather.defaultLocationName

    @State private var citySearchText  = ""
    @State private var isGeocoding     = false
    @State private var geocodeError    = false
    @State private var newSymbolText   = ""

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
                proLabel(Strings.Settings.showClockWidget, isPro: license.isPro)
            }
            .disabled(!license.isPro)
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
        }
        .formStyle(.grouped)
    }

    private var currentSymbols: [String] {
        StockTickerService.symbols(from: stockTickerSymbols)
    }

    private func addSymbol() {
        let candidate = newSymbolText.trimmingCharacters(in: .whitespaces).uppercased()
        guard !candidate.isEmpty, !currentSymbols.contains(candidate) else {
            newSymbolText = ""
            return
        }
        var updated = currentSymbols
        updated.append(candidate)
        stockTickerSymbols = updated.joined(separator: ",")
        newSymbolText = ""
    }

    private func removeSymbol(_ symbol: String) {
        let updated = currentSymbols.filter { $0 != symbol }
        stockTickerSymbols = updated.joined(separator: ",")
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

// MARK: - Pro Unlock

private struct ProUnlockTab: View {
    @Environment(LicenseManager.self) private var license
    @State private var licenseKeyInput = ""
    @State private var isActivating = false
    @State private var isDeactivating = false
    @State private var activationResult: ActivationResult? = nil
    @State private var deactivationError: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .padding(.top, 20)

                Text("DeskMat Pro")
                    .font(.title2)
                    .fontWeight(.semibold)

                if license.isPro {
                    activatedContent
                } else {
                    lockedContent
                }

                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
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
            }
            if let validated = license.lastValidated {
                Text(Strings.Pro.lastVerified(validated.formatted(date: .abbreviated, time: .shortened)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text(Strings.Pro.offlineBadge)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
            NSWorkspace.shared.open(URL(string: "https://cepholotech.lemonsqueezy.com/checkout/buy/e76ff2c0-32cd-41b7-b770-7b6b9873ab23")!)
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
                Strings.Pro.featureWeather,
                Strings.Pro.featureClock,
                Strings.Pro.featureLED,
                Strings.Pro.featureImage,
                Strings.Pro.featureSystem
            ], id: \.self) { label in
                Label(label, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
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
        let result = await license.deactivate()
        if case .error(let msg) = result { deactivationError = msg }
        isDeactivating = false
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
            Text("by Cepholotech LLC")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
