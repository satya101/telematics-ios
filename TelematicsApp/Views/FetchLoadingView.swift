import SwiftUI

/// Full-screen progress for an iLinkAir fetch: a radar sweeping from a High Site tower,
/// the current step, a live log count and a cancel button. With Reduce Motion on, the radar
/// and progress hold still and only the text and count change.
struct FetchLoadingView: View {
    let stage: ILinkAirStore.FetchStage
    let fetched: Int
    let expected: Int?
    let subtitle: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            RadarView()
                .frame(width: 220, height: 220)

            VStack(spacing: 8) {
                AnimatedTitle(text: stage.title)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Text(countText)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: fetched)
                ProgressStrip(fraction: fraction)
                    .frame(height: 6)
                    .padding(.horizontal, 40)
            }

            StepRow(current: stage)
                .padding(.horizontal, 24)

            Spacer(minLength: 0)
            Button(role: .cancel, action: onCancel) {
                Text("Cancel").frame(maxWidth: 220)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.opacity(0.96).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(stage.title), \(countText)")
    }

    private var countText: String {
        switch stage {
        case .signingIn: "Connecting to iLinkAir"
        case .exporting: fetched == 0 ? "Waiting for export…" : "\(fetched.formatted()) logs"
        case .parsing: "\(fetched.formatted()) logs"
        }
    }

    /// nil = indeterminate
    private var fraction: Double? {
        switch stage {
        case .signingIn: nil
        case .exporting: expected.flatMap { $0 > 0 && fetched > 0 ? min(1, Double(fetched) / Double($0)) : nil }
        case .parsing: nil
        }
    }
}

// MARK: - Radar

private struct RadarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Fixed "devices" on the scope: angle in degrees, radius as a fraction.
    private let blips: [(Double, Double)] = [(35, 0.62), (110, 0.38), (190, 0.8), (255, 0.55), (320, 0.3), (75, 0.86)]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let sweep = (t * 110).truncatingRemainder(dividingBy: 360)
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let r = size / 2
                ZStack {
                    // Scope grid
                    ForEach(1..<4) { i in
                        Circle().stroke(Theme.accent.opacity(0.15), lineWidth: 1)
                            .frame(width: size * Double(i) / 3, height: size * Double(i) / 3)
                    }
                    Path { p in
                        p.move(to: CGPoint(x: r, y: 0)); p.addLine(to: CGPoint(x: r, y: size))
                        p.move(to: CGPoint(x: 0, y: r)); p.addLine(to: CGPoint(x: size, y: r))
                    }
                    .stroke(Theme.accent.opacity(0.1), lineWidth: 1)

                    // Pulses radiating from the tower
                    ForEach(0..<3) { i in
                        let phase = (t / 2.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        Circle()
                            .stroke(Theme.accent.opacity(0.55 * (1 - phase)), lineWidth: 2)
                            .frame(width: size * (0.2 + 0.8 * phase), height: size * (0.2 + 0.8 * phase))
                    }

                    // Sweep with a fading tail
                    Circle()
                        .fill(AngularGradient(colors: [Theme.accent.opacity(0), Theme.accent.opacity(0), Theme.accent.opacity(0.45)],
                                              center: .center, startAngle: .degrees(0), endAngle: .degrees(360)))
                        .rotationEffect(.degrees(sweep - 90))
                        .frame(width: size, height: size)

                    // Blips light up as the sweep passes, then fade
                    ForEach(blips.indices, id: \.self) { i in
                        let (angle, radius) = blips[i]
                        let behind = (sweep - angle + 360).truncatingRemainder(dividingBy: 360)
                        let glow = max(0, 1 - behind / 200)
                        Circle()
                            .fill(Theme.green)
                            .frame(width: 8, height: 8)
                            .shadow(color: Theme.green, radius: 6 * glow)
                            .opacity(0.1 + 0.9 * glow)
                            .scaleEffect(0.7 + 0.5 * glow)
                            .offset(x: cos((angle - 90) * .pi / 180) * r * radius,
                                    y: sin((angle - 90) * .pi / 180) * r * radius)
                    }

                    // Tower
                    ZStack {
                        Circle().fill(Theme.card).frame(width: 64, height: 64)
                            .overlay(Circle().stroke(Theme.accent.opacity(0.6), lineWidth: 1.5))
                            .shadow(color: Theme.accent.opacity(0.5), radius: 12)
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
                    }
                }
                .frame(width: size, height: size)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Pieces

private struct AnimatedTitle: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Text(text + "…").font(.title3.weight(.bold))
        } else {
            dots
        }
    }

    private var dots: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { context in
            let dots = Int(context.date.timeIntervalSinceReferenceDate / 0.4) % 4
            Text(text + String(repeating: ".", count: dots) + String(repeating: " ", count: 3 - dots))
                .font(.title3.weight(.bold).monospaced())
                .foregroundStyle(.primary)
        }
    }
}

private struct ProgressStrip: View {
    let fraction: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.card)
                if let fraction {
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.accent, Theme.green], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * fraction))
                        .animation(.easeOut(duration: 0.3), value: fraction)
                } else if reduceMotion {
                    Capsule().fill(Theme.accent.opacity(0.4))
                } else {
                    TimelineView(.animation) { context in
                        let phase = (context.date.timeIntervalSinceReferenceDate / 1.3).truncatingRemainder(dividingBy: 1)
                        let w = geo.size.width * 0.35
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.accent.opacity(0), Theme.accent, Theme.accent.opacity(0)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: w)
                            .offset(x: -w + (geo.size.width + w) * phase)
                    }
                }
            }
            .clipShape(Capsule())
        }
    }
}

private struct StepRow: View {
    let current: ILinkAirStore.FetchStage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ILinkAirStore.FetchStage.allCases, id: \.self) { step in
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(step < current ? Theme.green : step == current ? Theme.accent : Theme.card)
                            .frame(width: 26, height: 26)
                        if step < current {
                            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Theme.bg)
                        } else if step == current {
                            if reduceMotion {
                                Circle().stroke(Theme.accent.opacity(0.6), lineWidth: 2).frame(width: 34, height: 34)
                            } else {
                                Circle().stroke(Theme.accent, lineWidth: 2).frame(width: 34, height: 34)
                                    .phaseAnimator([false, true]) { ring, on in
                                        ring.scaleEffect(on ? 1.2 : 0.9).opacity(on ? 0.1 : 0.8)
                                    } animation: { _ in .easeInOut(duration: 0.8) }
                            }
                            Text("\(step.rawValue + 1)").font(.caption.weight(.bold)).foregroundStyle(Theme.bg)
                        } else {
                            Text("\(step.rawValue + 1)").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(height: 34)
                    Text(step.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(step <= current ? .primary : Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .animation(reduceMotion ? nil : .spring(duration: 0.4), value: current)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(step.rawValue + 1), \(step.title), " + (step < current ? "done" : step == current ? "in progress" : "not started"))
            }
        }
    }
}

#Preview {
    FetchLoadingView(stage: .exporting, fetched: 1240, expected: 3000,
                     subtitle: "1 Oct 2026 – 3 Oct 2026 · IMEI 352648065204596", onCancel: {})
}
