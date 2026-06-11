import SwiftUI

struct EveWidget: View {
    static let cellCount = 2
    @Environment(EveService.self) private var eveService
    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("eveWidgetTheme") private var theme: EveWidgetTheme = .auto

    private var effectiveTheme: EveWidgetTheme {
        guard theme == .auto else { return theme }
        let resolved = EveWidgetTheme.from(raceId: eveService.shipRaceId)
        if resolved != .auto { return resolved }
        return EveWidgetTheme.from(raceId: eveService.characterRaceId)
    }

    var body: some View {
        VStack(spacing: 10) {
            DockWidget(cells: 2, isLoading: eveService.isLoading, backgroundColor: effectiveTheme == .auto ? nil : .clear, onRefresh: { await eveService.refresh() }) {
                if eveService.auth.isAuthenticated {
                    characterContent
                } else {
                    notConnectedContent
                }
            }
            .background {
                if effectiveTheme != .auto, let color = effectiveTheme.color {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color)
                        .widgetShader(EveHologramEffect(
                            intensity: eveService.isLoading ? 0 : 0.6,
                            tint: color
                        ))
                }
            }
            if showLabels {
                Text(Strings.Eve.widgetLabel)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: DockWidget<EmptyView>.width(for: Self.cellCount))
            }
        }
        .task {
            while !Task.isCancelled {
                await eveService.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private var portraitURL: URL? {
        guard eveService.auth.characterId > 0 else { return nil }
        return URL(string: "https://imageserver.eveonline.com/Character/\(eveService.auth.characterId)_128.jpg")
    }

    @ViewBuilder
    private var characterContent: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(eveService.auth.characterName)
                        .font(.custom("Exo 2", size: 8))
                        .foregroundStyle(effectiveTheme.labelTint.opacity(0.6))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Circle()
                        .fill(eveService.isOnline ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 6, height: 6)
                }
                if !eveService.locationName.isEmpty || !eveService.shipName.isEmpty {
                    Text([eveService.locationName, eveService.shipName]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.custom("Exo 2", size: 10).weight(.semibold))
                        .foregroundStyle(effectiveTheme.labelTint)
                        .lineLimit(1)
                }
                if !eveService.walletFormatted.isEmpty {
                    Text(eveService.walletFormatted)
                        .font(.custom("Exo 2", size: 8))
                        .foregroundStyle(effectiveTheme.labelTint.opacity(0.75))
                }
                if !eveService.trainingSkill.isEmpty {
                    Text("\(eveService.trainingSkill) · \(eveService.trainingRemaining)")
                        .font(.custom("Exo 2", size: 7))
                        .foregroundStyle(effectiveTheme.labelTint.opacity(0.5))
                        .lineLimit(1)
                }
                if eveService.isAuthFailed {
                    Text("Session expired — reconnect")
                        .font(.custom("Exo 2", size: 7))
                        .foregroundStyle(Color.orange.opacity(0.9))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var notConnectedContent: some View {
        Text(Strings.Eve.notConnected)
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
            .multilineTextAlignment(.center)
            .padding(8)
            .shadow(color: .black, radius: 0, x: 0, y: 1)
    }
}
