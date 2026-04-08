import SwiftUI
import ServiceManagement
import StoreKit
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
    HStack(spacing: 6) {
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
    @State private var showingClearCacheConfirmation = false
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

                VStack(alignment: .leading, spacing: 6) {
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
                    Text("Clears cached icon images. Icons will reload automatically on next launch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, 52)
                }
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
            Section {
                Toggle(isOn: $showSystemWidget) {
                    proLabel(Strings.Settings.showSystemWidget, isPro: entitlements.isPro)
                }
                .disabled(!entitlements.isPro)
                if showSystemWidget && entitlements.isPro {
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
    @Environment(EntitlementManager.self) private var entitlements
    @State private var isPurchasing = false
    @State private var transientMessage: String? = nil

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

                if entitlements.isPro {
                    unlockedContent
                } else {
                    lockedContent
                }

                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var unlockedContent: some View {
        VStack(spacing: 8) {
            Text(Strings.Pro.headlineUnlocked)
                .font(.headline)
            Text(Strings.Pro.confirmedBody)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        featureList
    }

    @ViewBuilder
    private var lockedContent: some View {
        VStack(spacing: 6) {
            Text(Strings.Pro.headlineLocked)
                .font(.headline)
            Text(Strings.Pro.subheadline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }

        featureList

        VStack(spacing: 10) {
            if isPurchasing {
                ProgressView(Strings.Pro.pendingLabel)
                    .controlSize(.regular)
            } else {
                Button(action: startPurchase) {
                    Text(entitlements.product.map { Strings.Pro.unlockCTAWithPrice($0.displayPrice) } ?? Strings.Pro.unlockCTA)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Button(Strings.Pro.restoreCTA) {
                Task {
                    isPurchasing = true
                    await entitlements.restorePurchases()
                    isPurchasing = false
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.footnote)
            .disabled(isPurchasing)

            if let message = transientMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Pro.featuresHeader)
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

    private func startPurchase() {
        isPurchasing = true
        transientMessage = nil
        Task {
            do {
                let result = try await entitlements.purchase()
                switch result {
                case .success:
                    break // isPro flips automatically via EntitlementManager
                case .pending:
                    transientMessage = Strings.Pro.pendingLabel
                case .cancelled:
                    break
                }
            } catch {
                transientMessage = error.localizedDescription
            }
            isPurchasing = false
        }
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
