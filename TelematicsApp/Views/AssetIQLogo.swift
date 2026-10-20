import SwiftUI

/// AssetIQ mark: a solar-powered trip-logging unit sending a GPS fix, over a logged route.
/// Pure SwiftUI shapes so the same drawing renders the app icon (see scripts/render_icon.swift).
struct AssetIQLogo: View {
    var cornerRadius: CGFloat? = nil   // nil = icon-style squircle radius

    private static let navyTop = Color(red: 0.075, green: 0.137, blue: 0.227)
    private static let navyBottom = Color(red: 0.043, green: 0.055, blue: 0.078)
    private static let body = Color(red: 0.102, green: 0.122, blue: 0.180)
    private static let panel = Color(red: 0.055, green: 0.196, blue: 0.345)
    private static let cyan = Color(red: 0, green: 0.831, blue: 1)
    private static let green = Color(red: 0, green: 0.898, blue: 0.478)

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius ?? s * 0.22, style: .continuous)
                    .fill(LinearGradient(colors: [Self.navyTop, Self.navyBottom], startPoint: .top, endPoint: .bottom))

                route(s)
                    .stroke(Self.cyan.opacity(0.85), style: StrokeStyle(lineWidth: s * 0.035, lineCap: .round, dash: [s * 0.06, s * 0.045]))
                Circle().fill(Self.green).frame(width: s * 0.085).position(x: s * 0.16, y: s * 0.84)
                pin(s)

                device(s).position(x: s * 0.44, y: s * 0.44)
                signal(s)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func route(_ s: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: s * 0.16, y: s * 0.84))
            p.addCurve(to: CGPoint(x: s * 0.80, y: s * 0.78),
                       control1: CGPoint(x: s * 0.40, y: s * 0.68),
                       control2: CGPoint(x: s * 0.58, y: s * 0.96))
        }
    }

    private func pin(_ s: CGFloat) -> some View {
        Image(systemName: "mappin.circle.fill")
            .resizable()
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color(red: 1, green: 0.267, blue: 0.267))
            .frame(width: s * 0.17, height: s * 0.17)
            .position(x: s * 0.80, y: s * 0.74)
    }

    /// Logger unit with a solar panel face and a status LED.
    private func device(_ s: CGFloat) -> some View {
        let w = s * 0.50, h = s * 0.36
        return ZStack {
            RoundedRectangle(cornerRadius: s * 0.06, style: .continuous)
                .fill(Self.body)
                .overlay(RoundedRectangle(cornerRadius: s * 0.06, style: .continuous).stroke(Self.cyan, lineWidth: s * 0.02))
            // Solar panel: 4×2 cells
            VStack(spacing: s * 0.012) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: s * 0.012) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: s * 0.008).fill(Self.panel)
                                .overlay(RoundedRectangle(cornerRadius: s * 0.008).stroke(Self.cyan.opacity(0.35), lineWidth: s * 0.004))
                        }
                    }
                }
            }
            .padding(.horizontal, w * 0.12)
            .padding(.top, h * 0.16)
            .padding(.bottom, h * 0.30)
            Circle().fill(Self.green).frame(width: s * 0.035)
                .position(x: w * 0.86, y: h * 0.84)
        }
        .frame(width: w, height: h)
    }

    /// GPS signal arcs off the unit's top-right corner.
    private func signal(_ s: CGFloat) -> some View {
        let c = CGPoint(x: s * 0.68, y: s * 0.30)
        return ZStack {
            ForEach(1..<4, id: \.self) { i in
                Path { p in
                    p.addArc(center: c, radius: s * (0.05 + 0.06 * CGFloat(i)),
                             startAngle: .degrees(-80), endAngle: .degrees(-10), clockwise: false)
                }
                .stroke(Self.cyan.opacity(1 - 0.22 * Double(i - 1)), style: StrokeStyle(lineWidth: s * 0.032, lineCap: .round))
            }
        }
    }
}
