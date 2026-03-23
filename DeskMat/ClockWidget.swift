import SwiftUI

struct ClockWidget: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            DockWidget(width: 96) {
                VStack(spacing: 6) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(context.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.15), in: Capsule())
                }
            }
        }
        .onTapGesture {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.clock") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
