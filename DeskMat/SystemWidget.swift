import SwiftUI

struct SystemWidget: View {
    static let cellCount = 1

    @Environment(SystemMonitorService.self) private var monitor
    @AppStorage("showLabels")      private var showLabels = true
    @AppStorage("sysWidgetMetric") private var metric: SystemMetric = .cpu

    var body: some View {
        VStack(spacing: 10) {
            DockWidget {
                switch metric {
                case .cpu:     CPUView(percent: monitor.cpuPercent)
                case .ram:     RAMView(used: monitor.ramUsedGB, total: monitor.ramTotalGB)
                case .network: NetworkView(inKBs: monitor.netInKBs, outKBs: monitor.netOutKBs)
                }
            }
            if showLabels {
                Text(metric.rawValue)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: DockWidget<EmptyView>.width(for: Self.cellCount))
                    .truncationMode(.tail)
            }
        }
        .onAppear { monitor.start() }
    }
}

// MARK: - CPU

private struct CPUView: View {
    let percent: Double

    var body: some View {
        VStack(spacing: 6) {
            Text("CPU")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            MeterBar(value: percent)
            Text("\(Int(percent * 100))%")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
    }
}

// MARK: - RAM

private struct RAMView: View {
    let used: Double
    let total: Double

    private var fraction: Double {
        total > 0 ? min(used / total, 1.0) : 0
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("RAM")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            MeterBar(value: fraction)
            Text(String(format: "%.1f / %.0f", used, total))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
            Text("GiB")
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 10)
    }
}

// MARK: - Network

private struct NetworkView: View {
    let inKBs: Double
    let outKBs: Double

    var body: some View {
        VStack(spacing: 4) {
            Text("NET")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            VStack(spacing: 3) {
                NetRow(direction: "arrow.down", value: inKBs)
                NetRow(direction: "arrow.up",   value: outKBs)
            }
        }
        .padding(.horizontal, 8)
    }
}

private struct NetRow: View {
    let direction: String
    let value: Double

    private var formatted: (value: String, unit: String) {
        value >= 1024
            ? (String(format: "%.1f", value / 1024), "MB/s")
            : (String(format: "%.1f", value),         "KB/s")
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: direction)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text(formatted.value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            Text(formatted.unit)
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

// MARK: - Shared Meter Bar

private struct MeterBar: View {
    let value: Double

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.15))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.8))
                    .scaleEffect(x: max(0, min(value, 1)), anchor: .leading)
            }
            .frame(height: 4)
            .animation(.easeOut(duration: 0.3), value: value)
    }
}
