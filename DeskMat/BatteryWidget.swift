import SwiftUI
import IOKit.ps

struct BatteryWidget: View {
    @State private var batteryLevel: Double = 0
    @State private var isCharging: Bool = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            DockWidget(width: 64) {
                ZStack(alignment: .bottom) {
                    // Battery fill
                    GeometryReader { geo in
                        let fillHeight = geo.size.height * batteryLevel / 100
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                ColorUtils.darkened(batteryColor)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(batteryColor, lineWidth: 2)
                            )
                            .frame(height: fillHeight)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }

                    // Percentage text
                    VStack(spacing: 6) {
                        if isCharging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.white)
                        }
                        Text("\(Int(batteryLevel))%")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { updateBattery() }
        .onChange(of: batteryLevel) { _, _ in } // triggers redraw
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                updateBattery()
            }
        }
    }

    private var batteryColor: Color {
        if isCharging { return .green }
        if batteryLevel <= 20 { return .red }
        if batteryLevel <= 40 { return .orange }
        return .green
    }

    private func updateBattery() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let info = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: Any] else {
            return
        }

        if let capacity = info[kIOPSCurrentCapacityKey] as? Int {
            batteryLevel = Double(capacity)
        }
        if let charging = info[kIOPSIsChargingKey] as? Bool {
            isCharging = charging
        }
    }
}
