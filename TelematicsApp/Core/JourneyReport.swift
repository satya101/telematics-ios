import Foundation

enum TripType: String, CaseIterable, Identifiable, Codable {
    case business = "Business"
    case personal = "Personal"
    case maintenance = "Maintenance"
    case delivery = "Delivery"
    case serviceCall = "Service Call"

    var id: String { rawValue }
}

/// One editable row of the Journey Summary Report.
struct JourneyRow: Identifiable, Hashable {
    let trip: Trip
    var asset: String?          // nil = use the report default
    var driver: String?
    var type: TripType?
    var startLocation: String?  // reverse geocoded; nil while locating
    var endLocation: String?

    var id: Int { trip.id }
}

enum JourneyReport {
    static let headers = ["Trip", "Asset Name", "Start Date", "Start Time", "End Date", "End Time",
                          "Type", "Max Speed (km/h)", "Duration", "Distance (km)",
                          "Start Location", "End Location", "Driver", "Trip Close"]

    static func csv(rows: [JourneyRow], defaultAsset: String, defaultDriver: String, defaultType: TripType) -> String {
        var lines = [headers]
        for row in rows {
            let s = row.trip.summary
            lines.append([
                "T\(row.trip.id)",
                row.asset ?? defaultAsset,
                MelbourneTime.fullDate(s.start),
                MelbourneTime.time(s.start),
                MelbourneTime.fullDate(s.end),
                MelbourneTime.time(s.end),
                (row.type ?? defaultType).rawValue,
                String(format: "%.1f", s.maxSpeed),
                MelbourneTime.duration(minutes: s.durationMin),
                String(format: "%.2f", s.distanceKm),
                row.startLocation ?? "",
                row.endLocation ?? "",
                row.driver ?? defaultDriver,
                s.closedByDP4 ? "DP4 Clean" : "Timeout",
            ])
        }
        return lines
            .map { $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }
            .joined(separator: "\r\n")
    }

    static func summaryLine(_ trips: [Trip]) -> String {
        let km = trips.reduce(0) { $0 + $1.summary.distanceKm }
        let min = trips.reduce(0) { $0 + $1.summary.durationMin }
        let top = trips.map(\.summary.maxSpeed).max() ?? 0
        return "\(trips.count) trips · \(String(format: "%.1f", km)) km total · "
            + "\(MelbourneTime.duration(minutes: min)) total drive time · Max speed \(String(format: "%.0f", top)) km/h"
    }
}
