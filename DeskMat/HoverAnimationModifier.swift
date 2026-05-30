import SwiftUI

// Drives scale/rotation/shine hover animations on any dock icon.
// Callers keep their own @State isHovering and pass it as a binding;
// this modifier observes changes and runs the selected animation.
struct HoverAnimationModifier: ViewModifier {
    let isReordering: Bool
    @Binding var isHovering: Bool

    @AppStorage("hoverSize") private var hoverSize: HoverSize = .small
    @AppStorage("hoverAnimation") private var hoverAnimation: HoverAnimation = .bounce

    @State private var bobScale: Double = 1.0
    @State private var jiggleAngle: Double = 0
    @State private var hoverStartDate: Date? = nil

    func body(content: Content) -> some View {
        content
            .modifier(HoverShineModifier(hoverStartDate: hoverAnimation == .shine ? hoverStartDate : nil))
            .scaleEffect(bobScale)
            .rotationEffect(.degrees(jiggleAngle))
            .onChange(of: isHovering) { _, hovering in
                if hovering && !isReordering {
                    if hoverAnimation == .shine { hoverStartDate = Date.now }
                    startAnimation()
                } else if !hovering {
                    hoverStartDate = nil
                    withAnimation(.easeOut(duration: 0.2)) {
                        bobScale = 1.0
                        jiggleAngle = 0
                    }
                }
            }
    }

    private func startAnimation() {
        switch hoverAnimation {
        case .bounce: animateBounce()
        case .pulse:  animatePulse()
        case .jiggle: animateJiggle()
        case .pop:    animatePop()
        case .shine, .none: break
        }
    }

    private func animateBounce() {
        let a = hoverSize.scale - 1.0
        let bounces: [(amplitude: Double, duration: Double)] = [
            (a,        0.08), (a * 0.65, 0.06), (a * 0.40, 0.05),
            (a * 0.25, 0.05), (a * 0.15, 0.04), (a * 0.08, 0.04), (a * 0.03, 0.03),
        ]
        Task {
            for (i, bounce) in bounces.enumerated() {
                guard isHovering else { break }
                let target = (i % 2 == 0) ? 1.0 + bounce.amplitude : 1.0 - bounce.amplitude * 0.5
                withAnimation(.easeInOut(duration: bounce.duration)) { bobScale = target }
                try? await Task.sleep(for: .milliseconds(Int(bounce.duration * 1000)))
            }
            guard isHovering else { return }
            withAnimation(.easeOut(duration: 0.04)) { bobScale = 1.0 }
        }
    }

    private func animatePulse() {
        Task {
            guard isHovering else { return }
            withAnimation(.easeInOut(duration: 0.2)) { bobScale = hoverSize.scale }
            try? await Task.sleep(for: .milliseconds(200))
            guard isHovering else { return }
            withAnimation(.easeInOut(duration: 0.2)) { bobScale = 1.0 }
        }
    }

    private func animateJiggle() {
        let steps: [(angle: Double, duration: Double)] = [
            ( 4, 0.05), (-4, 0.05), ( 3, 0.04), (-3, 0.04),
            ( 2, 0.04), (-2, 0.04), ( 1, 0.03), (-1, 0.03), (0, 0.03),
        ]
        Task {
            for step in steps {
                guard isHovering else { break }
                withAnimation(.easeInOut(duration: step.duration)) { jiggleAngle = step.angle }
                try? await Task.sleep(for: .milliseconds(Int(step.duration * 1000)))
            }
            guard isHovering else { return }
            withAnimation(.easeOut(duration: 0.03)) { jiggleAngle = 0 }
        }
    }

    private func animatePop() {
        bobScale = hoverSize.scale
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { bobScale = 1.0 }
    }
}

// MARK: - Shine Modifier

struct HoverShineModifier: ViewModifier {
    let hoverStartDate: Date?

    func body(content: Content) -> some View {
        if let startDate = hoverStartDate {
            TimelineView(.animation) { ctx in
                let elapsed = ctx.date.timeIntervalSince(startDate)
                content
                    .layerEffect(
                        ShaderLibrary.shineGlint(
                            .float(Float(elapsed)),
                            .float(64),
                            .float(64)
                        ),
                        maxSampleOffset: .zero
                    )
            }
        } else {
            content
        }
    }
}

// MARK: - Convenience

extension View {
    func hoverAnimation(isReordering: Bool, isHovering: Binding<Bool>) -> some View {
        modifier(HoverAnimationModifier(isReordering: isReordering, isHovering: isHovering))
    }
}
