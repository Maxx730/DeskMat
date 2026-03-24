import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("showWeatherWidget") private var showWeatherWidget = true
    @AppStorage("hoverSize") private var hoverSize: HoverSize = .small
    @AppStorage("hoverAnimation") private var hoverAnimation: HoverAnimation = .bounce
    @AppStorage("dockPosition") private var dockPosition: DockPosition = .bottom
    @AppStorage("dockOffset") private var dockOffset = 0
    @AppStorage("finderDefaultDirectory") private var finderDefaultDirectory = "~/"
    @AppStorage("showClockWidget") private var showClockWidget = true
    @AppStorage("showBatteryWidget") private var showBatteryWidget = true
    @AppStorage("showBatteryPercentage") private var showBatteryPercentage = true
    @AppStorage("dockEffect") private var dockEffect: DockEffect = .rainbow
    @AppStorage("visualEffect") private var visualEffect: VisualEffect = .none
    @AppStorage("dockItemShaderIntensity") private var dockItemShaderIntensity = 0.5


    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left column: General + Appearance
            VStack(alignment: .leading, spacing: 8) {
                SettingsSection(title: Strings.Settings.general) {
                    VStack(spacing: 12) {
                        HStack {
                            Text(Strings.Settings.launchAtLogin)
                            Spacer()
                            Toggle("", isOn: $launchAtLogin)
                                .labelsHidden()
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
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(Strings.Settings.finderDefaultDirectory)
                                Spacer()
                                TextField("", text: $finderDefaultDirectory)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 150)
                                    .multilineTextAlignment(.trailing)
                            }
                            Text(Strings.Settings.finderDefaultDirectorySublabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                SettingsSection(title: Strings.Settings.appearance) {
                    VStack(spacing: 12) {
                        HStack {
                            Text(Strings.Settings.showLabels)
                            Spacer()
                            Toggle("", isOn: $showLabels)
                                .labelsHidden()
                        }
                        Divider()
                        HStack {
                            Text(Strings.Settings.visualEffect)
                            Spacer()
                            Picker("", selection: $visualEffect) {
                                ForEach(VisualEffect.allCases, id: \.self) { effect in
                                    Text(effect.rawValue).tag(effect)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        if visualEffect != .none {
                            Divider()
                            HStack {
                                Text(Strings.Settings.effectIntensity)
                                Spacer()
                                Slider(value: $dockItemShaderIntensity, in: 0.0...1.0)
                                    .frame(width: 120)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Right column: Hover + Dock
            VStack(alignment: .leading, spacing: 8) {
                SettingsSection(title: Strings.Settings.hover) {
                    VStack(spacing: 12) {
                        HStack {
                            Text(Strings.Settings.scale)
                            Spacer()
                            Picker("", selection: $hoverSize) {
                                ForEach(HoverSize.allCases, id: \.self) { size in
                                    Text(size.rawValue).tag(size)
                                }
                            }
                            .labelsHidden()
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        Divider()
                        HStack {
                            Text(Strings.Settings.animation)
                            Spacer()
                            Picker("", selection: $hoverAnimation) {
                                ForEach(HoverAnimation.allCases, id: \.self) { style in
                                    Text(style.rawValue).tag(style)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }
                SettingsSection(title: Strings.Settings.widgets) {
                    VStack(spacing: 12) {
                        HStack {
                            Text(Strings.Settings.showWeatherWidget)
                            Spacer()
                            Toggle("", isOn: $showWeatherWidget)
                                .labelsHidden()
                        }
                        Divider()
                        HStack {
                            Text(Strings.Settings.showClockWidget)
                            Spacer()
                            Toggle("", isOn: $showClockWidget)
                                .labelsHidden()
                        }
                        Divider()
                        HStack {
                            Text(Strings.Settings.showBatteryWidget)
                            Spacer()
                            Toggle("", isOn: $showBatteryWidget)
                                .labelsHidden()
                        }
                        Divider()
                        HStack {
                            Text(Strings.Settings.showBatteryPercentage)
                            Spacer()
                            Toggle("", isOn: $showBatteryPercentage)
                                .labelsHidden()
                        }
                    }
                }
                SettingsSection(title: Strings.Settings.dock) {
                    VStack(spacing: 12) {
                        HStack {
                            Text(Strings.Settings.position)
                            Spacer()
                            Picker("", selection: $dockPosition) {
                                ForEach(DockPosition.allCases, id: \.self) { position in
                                    Text(position.rawValue).tag(position)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        Divider()
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
                        Divider()
                        HStack {
                            Text(Strings.Settings.borderEffect)
                            Spacer()
                            Picker("", selection: $dockEffect) {
                                ForEach(DockEffect.allCases, id: \.self) { effect in
                                    Text(effect.rawValue).tag(effect)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
    }
}
