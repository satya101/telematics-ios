import SwiftUI
import CoreLocation
import UIKit

/// Colours and scales carried over from the web dashboard. Each colour has a light and a
/// dark variant (the dark ones are the website's), plus stronger ones for Increase Contrast,
/// so the app follows the system appearance. Text colours meet 4.5:1 on their backgrounds.
enum Theme {
    static let bg = dynamic(light: 0xF2F4F8, dark: 0x0B0E14)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x131720)
    static let card = dynamic(light: 0xE6EAF2, dark: 0x1A1F2E)
    static let border = dynamic(light: 0xD3D9E4, dark: 0x252B3B)
    static let accent = dynamic(light: 0x0072A3, dark: 0x00D4FF, lightHC: 0x005478, darkHC: 0x6BE6FF)
    static let green = dynamic(light: 0x0A7F45, dark: 0x00E57A, lightHC: 0x065E33, darkHC: 0x5CF5A8)
    static let yellow = dynamic(light: 0x8A5F00, dark: 0xFFC107, lightHC: 0x664600, darkHC: 0xFFD54F)
    static let red = dynamic(light: 0xC81E1E, dark: 0xFF5A5A, lightHC: 0x9A1212, darkHC: 0xFF8A8A)
    static let purple = dynamic(light: 0x7E36C9, dark: 0xB57BFA, lightHC: 0x5F2499, darkHC: 0xCFA6FF)
    static let lime = dynamic(light: 0x4E8A1A, dark: 0x80E040)
    static let orange = dynamic(light: 0xB85A00, dark: 0xFF8C00)
    /// Secondary text uses the system colour, which keeps its contrast in every appearance.
    static let muted = Color.secondary

    static func speedColor(_ v: Double) -> Color {
        v < 20 ? green : v < 50 ? lime : v < 80 ? yellow : v < 100 ? orange : red
    }

    static func hdopColor(_ v: Double) -> Color {
        v < 1.5 ? green : v < 3 ? lime : v < 5 ? yellow : v < 10 ? orange : red
    }

    static func hdopLabel(_ v: Double) -> String {
        v < 1.5 ? "Excellent" : v < 3 ? "Good" : v < 5 ? "Moderate" : v < 10 ? "Poor" : "Invalid"
    }

    static func dataPointLabel(_ dp: Int) -> String {
        dp == 2 ? "DP2 Heartbeat" : dp == 4 ? "DP4 Trip End" : "DP3 Data"
    }

    static let speedLegend: [(Color, String)] = [
        (green, "< 20 km/h"), (lime, "20–50 km/h"), (yellow, "50–80 km/h"),
        (orange, "80–100 km/h"), (red, "> 100 km/h"),
    ]
    static let hdopLegend: [(Color, String)] = [
        (green, "< 1.5 Excellent"), (lime, "1.5–3 Good"), (yellow, "3–5 Moderate"),
        (orange, "5–10 Poor"), (red, "> 10 Invalid"),
    ]

    /// Palette for the all-trips overview.
    static let tripPalette: [Color] = [0x00D4FF, 0x00E57A, 0xFF6B2B, 0xA855F7, 0xFFC107, 0xFF4444, 0x00BCD4, 0x8BC34A].map { Color(hex: $0) }
}

extension Theme {
    static func dynamic(light: UInt32, dark: UInt32, lightHC: UInt32? = nil, darkHC: UInt32? = nil) -> Color {
        Color(uiColor: UIColor { traits in
            let high = traits.accessibilityContrast == .high
            let hex = traits.userInterfaceStyle == .dark ? (high ? darkHC ?? dark : dark) : (high ? lightHC ?? light : light)
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension Ping {
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}
