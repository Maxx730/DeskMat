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


    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // General section
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
                                .frame(width: 200)
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
                }
            }
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
            SettingsSection (title: Strings.Settings.dock) {
                VStack(alignment: .leading, spacing: 0) {
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
                        }
                }
            }
        }
        .padding(16)
    }
}
