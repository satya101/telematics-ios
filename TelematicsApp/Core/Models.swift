import Foundation

/// Hardware revision of the tracker. v371 appends solar charging voltage (mV) at field 23.
enum BoardVersion: String, CaseIterable, Identifiable, Codable {
    case v370 = "370"
    case v371 = "371"

    var id: String { rawValue }
    var label: String { self == .v370 ? "v370 (V2 Board)" : "v371" }
}

/// Data Point type from payload field 15.
enum DataPoint: Int {
    case heartbeat = 2   // DP2: heartbeat / tentative start
    case data = 3        // DP3: regular data ping
    case tripEnd = 4     // DP4: explicit trip end
}

/// One GPS ping decoded from a CSV row's Payload field.
struct Ping: Identifiable, Hashable {
    let id: Int              // row index in the export, stable for selection
    let deviceID: String
    let firmware: String
    let date: Date           // UTC instant; display in Melbourne time via MelbourneTime
    let latitude: Double
    let longitude: Double
    let dataPoint: Int
    let movement: Int
    let speed: Double        // km/h
    let direction: Double    // degrees true north
    let elevation: Double    // m
    let hdop: Double         // 99 = no fix
    let odometerM: Int
    let usageMin: Int
    let solarMV: Double?
    let board: BoardVersion
}

struct TripSummary: Hashable {
    let dateKey: String      // YYYY-MM-DD, Melbourne calendar date of the start
    let start: Date
    let end: Date
    let durationMin: Double  // rounded to 0.1
    let distanceKm: Double   // rounded to 0.01, plausible odometer deltas only
    let maxSpeed: Double
    let avgSpeed: Double
    let avgHDOP: Double
    let odometerEndM: Int
    let pingCount: Int
    let dp2Count: Int
    let dp3Count: Int
    let closedByDP4: Bool
    let avgSolarMV: Int?
}

struct Trip: Identifiable, Hashable {
    let id: Int              // T-number, as on the website
    let pings: [Ping]
    let summary: TripSummary
}

/// Per-day raw ping stats, used to explain days with pings but no trips.
struct PingStats: Hashable {
    var pings = 0
    var noFix = 0
    var maxSpeed = 0.0
}
