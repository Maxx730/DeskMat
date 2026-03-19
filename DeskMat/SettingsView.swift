import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("hoverSize") private var hoverSize: HoverSize = .small
    @AppStorage("hoverAnimation") private var hoverAnimation: HoverAnimation = .bounce
    @AppStorage("dockPosition") private var dockPosition: DockPosition = .bottom
    @AppStorage("dockOffset") private var dockOffset = 0


    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // General section
            VStack(alignment: .leading, spacing: 0) {
                Text("General")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)

                VStack(spacing: 12) {
                    HStack {
                        Text("Launch at Login")
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
                }
                .padding(16)
                .background(.quinary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Text("Appearance")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
            // Appearance section
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 12) {
                    HStack {
                        Text("Show Labels")
                        Spacer()
                        Toggle("", isOn: $showLabels)
                            .labelsHidden()
                    }
                }
                .padding(16)
                .background(.quinary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Text("Hover")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
            VStack(alignment: .leading, spacing: 0) {
                
                VStack(spacing: 12) {
                    HStack {
                        Text("Scale")
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
                        Text("Animation")
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
            .padding(16)
            .background(.quinary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            Text("Dock")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
            VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Position")
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
                            Text("Offset")
                            Spacer()
                            TextField("", value: $dockOffset, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                                .multilineTextAlignment(.trailing)
                            Text("px")
                                .foregroundStyle(.secondary)
                        }
                    }
            }.padding(16)
            .background(.quinary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text("Icons")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
        }
        .padding(16)
    }
}
