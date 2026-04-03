import SwiftUI

struct OnboardingView: View {
    @State private var step = 0
    var onComplete: () -> Void

    private enum Step: Int, CaseIterable {
        case welcome, widgets, position, appearance, finish
    }

    var body: some View {
        VStack(spacing: 0) {
            StepIndicator(current: step, total: Step.allCases.count)
                .padding(.top, 24)

            Divider()
                .padding(.top, 16)

            Group {
                switch Step(rawValue: step) ?? .welcome {
                case .welcome:    WelcomeStep()
                case .widgets:    WidgetsStep()
                case .position:   PositionStep()
                case .appearance: AppearanceStep()
                case .finish:     FinishStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: step)

            Divider()

            NavigationRow(
                step: step,
                totalSteps: Step.allCases.count,
                onBack:     { withAnimation(.easeInOut(duration: 0.2)) { step -= 1 } },
                onNext:     { withAnimation(.easeInOut(duration: 0.2)) { step += 1 } },
                onComplete: onComplete
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 480, height: 380)
    }
}

// MARK: - Step Indicator

private struct StepIndicator: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
                    .animation(.easeInOut(duration: 0.2), value: current)
            }
        }
    }
}

// MARK: - Navigation Row

private struct NavigationRow: View {
    let step: Int
    let totalSteps: Int
    let onBack: () -> Void
    let onNext: () -> Void
    let onComplete: () -> Void

    private var isLast: Bool { step == totalSteps - 1 }

    var body: some View {
        HStack {
            if step > 0 {
                Button(Strings.Onboarding.back, action: onBack)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isLast {
                Button(Strings.Onboarding.skip, action: onComplete)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 12)
            }

            Button(isLast ? Strings.Onboarding.getStarted : Strings.Onboarding.next) {
                if isLast { onComplete() } else { onNext() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
        }
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            Text(Strings.Onboarding.Welcome.title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(Strings.Onboarding.Welcome.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
    }
}

// MARK: - Step 2: Widgets

private struct WidgetsStep: View {
    @AppStorage("showWeatherWidget") private var showWeatherWidget = true
    @AppStorage("showClockWidget")   private var showClockWidget   = true
    @AppStorage("showImageWidget")   private var showImageWidget   = true
    @AppStorage("showLEDBoard")      private var showLEDBoard      = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                title: Strings.Onboarding.Widgets.title,
                subtitle: Strings.Onboarding.Widgets.subtitle
            )

            VStack(spacing: 0) {
                WidgetRow(icon: "cloud.sun",   label: Strings.Onboarding.Widgets.weather,  isOn: $showWeatherWidget)
                Divider().padding(.leading, 44)
                WidgetRow(icon: "clock",       label: Strings.Onboarding.Widgets.clock,    isOn: $showClockWidget)
                Divider().padding(.leading, 44)
                WidgetRow(icon: "photo",       label: Strings.Onboarding.Widgets.image,    isOn: $showImageWidget)
                Divider().padding(.leading, 44)
                WidgetRow(icon: "lightbulb",   label: Strings.Onboarding.Widgets.ledBoard, isOn: $showLEDBoard)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
    }
}

private struct WidgetRow: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(label, systemImage: icon)
                .padding(.vertical, 10)
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 14)
    }
}

// MARK: - Step 3: Dock Position

private struct PositionStep: View {
    @AppStorage("dockPosition") private var dockPosition: DockPosition = .bottom

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                title: Strings.Onboarding.Position.title,
                subtitle: Strings.Onboarding.Position.subtitle
            )

            HStack(spacing: 16) {
                PositionCard(
                    label: Strings.Onboarding.Position.bottom,
                    systemImage: "dock.rectangle",
                    selected: dockPosition == .bottom
                ) { dockPosition = .bottom }

                PositionCard(
                    label: Strings.Onboarding.Position.top,
                    systemImage: "menubar.rectangle",
                    selected: dockPosition == .top
                ) { dockPosition = .top }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
    }
}

private struct PositionCard: View {
    let label: String
    let systemImage: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 32))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Text(label)
                    .font(.subheadline)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(selected ? Color.accentColor : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 4: Appearance

private struct AppearanceStep: View {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("dockBackground") private var dockBackground: DockBackground = .system

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                title: Strings.Onboarding.Appearance.title,
                subtitle: Strings.Onboarding.Appearance.subtitle
            )

            Form {
                Picker(Strings.Onboarding.Appearance.theme, selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker(Strings.Onboarding.Appearance.dockBackground, selection: $dockBackground) {
                    ForEach(DockBackground.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
    }
}

// MARK: - Step 5: Finish

private struct FinishStep: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)

            Text(Strings.Onboarding.Finish.title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(Strings.Onboarding.Finish.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
    }
}

// MARK: - Shared Header

private struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
