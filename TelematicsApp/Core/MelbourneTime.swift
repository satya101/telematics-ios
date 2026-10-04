import Foundation

/// All times are shown in Melbourne local time (AEST/AEDT), using the system
/// time zone database so daylight-saving switchovers land on the right hour.
enum MelbourneTime {
    static let zone = TimeZone(identifier: "Australia/Melbourne")!

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }()

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU_POSIX")
        f.timeZone = zone
        f.dateFormat = format
        return f
    }

    private static let timeF = formatter("HH:mm:ss")
    private static let shortDateF = formatter("d MMM")
    private static let fullDateF = formatter("d MMM yyyy")
    private static let keyF = formatter("yyyy-MM-dd")

    static func time(_ d: Date) -> String { timeF.string(from: d) }
    static func shortDate(_ d: Date) -> String { shortDateF.string(from: d) }
    static func fullDate(_ d: Date) -> String { fullDateF.string(from: d) }
    static func dateKey(_ d: Date) -> String { keyF.string(from: d) }
    static func fullDate(key: String) -> String {
        keyF.date(from: key).map { fullDate($0) } ?? key
    }

    /// "UTC+10" or "UTC+11"
    static func offsetLabel(_ d: Date) -> String {
        "UTC+\(zone.secondsFromGMT(for: d) / 3600)"
    }

    /// "AEST" or "AEDT"
    static func abbreviation(_ d: Date) -> String {
        zone.isDaylightSavingTime(for: d) ? "AEDT" : "AEST"
    }

    /// "1h 5m" or "12m"
    static func duration(minutes: Double) -> String {
        let h = Int(minutes / 60)
        let m = Int((minutes.truncatingRemainder(dividingBy: 60)).rounded())
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
