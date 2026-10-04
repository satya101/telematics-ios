import SwiftUI
import CoreLocation

/// Colours and scales carried over from the web dashboard.
enum Theme {
    static let bg = Color(hex: 0x0B0E14)
    static let surface = Color(hex: 0x131720)
    static let card = Color(hex: 0x1A1F2E)
    static let border = Color(hex: 0x252B3B)
    static let accent = Color(hex: 0x00D4FF)
    static let green = Color(hex: 0x00E57A)
    static let yellow = Color(hex: 0xFFC107)
    static let red = Color(hex: 0xFF4444)
    static let purple = Color(hex: 0xA855F7)
    static let muted = Color(hex: 0x6B7490)

    static func speedColor(_ v: Double) -> Color {
        v < 20 ? green : v < 50 ? Color(hex: 0x80E040) : v < 80 ? yellow : v < 100 ? Color(hex: 0xFF8C00) : red
    }

    static func hdopColor(_ v: Double) -> Color {
        v < 1.5 ? green : v < 3 ? Color(hex: 0x80E040) : v < 5 ? yellow : v < 10 ? Color(hex: 0xFF8C00) : red
    }

    static func hdopLabel(_ v: Double) -> String {
        v < 1.5 ? "Excellent" : v < 3 ? "Good" : v < 5 ? "Moderate" : v < 10 ? "Poor" : "Invalid"
    }

    static func dataPointLabel(_ dp: Int) -> String {
        dp == 2 ? "DP2 Heartbeat" : dp == 4 ? "DP4 Trip End" : "DP3 Data"
    }

    static let speedLegend: [(Color, String)] = [
        (green, "< 20 km/h"), (Color(hex: 0x80E040), "20–50 km/h"), (yellow, "50–80 km/h"),
        (Color(hex: 0xFF8C00), "80–100 km/h"), (red, "> 100 km/h"),
    ]
    static let hdopLegend: [(Color, String)] = [
        (green, "< 1.5 Excellent"), (Color(hex: 0x80E040), "1.5–3 Good"), (yellow, "3–5 Moderate"),
        (Color(hex: 0xFF8C00), "5–10 Poor"), (red, "> 10 Invalid"),
    ]

    /// Palette for the all-trips overview.
    static let tripPalette: [Color] = [0x00D4FF, 0x00E57A, 0xFF6B2B, 0xA855F7, 0xFFC107, 0xFF4444, 0x00BCD4, 0x8BC34A].map { Color(hex: $0) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension Ping {
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}
