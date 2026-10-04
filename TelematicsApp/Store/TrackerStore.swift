import Foundation
import Observation

/// Holds the loaded export and everything derived from it.
@MainActor
@Observable
final class TrackerStore {
    // Source
    private(set) var fileName: String?
    private var rawText: String?
    private(set) var board: BoardVersion = .v370

    // Derived
    private(set) var pings: [Ping] = []
    private(set) var trips: [Trip] = []
    private(set) var dateKeys: [String] = []            // every Melbourne date present in the export
    private(set) var tripsByDate: [String: [Trip]] = [:]
    private(set) var statsByDate: [String: PingStats] = [:]
    private(set) var skipped = 0
    private(set) var skippedStatusMessages = 0

    // UI state
    var activeDate: String?                             // nil = all dates
    private(set) var isLoading = false
    var errorMessage: String?

    var visibleTrips: [Trip] { activeDate.map { tripsByDate[$0] ?? [] } ?? trips }
    var hasData: Bool { !pings.isEmpty }
    var deviceID: String { pings.first?.deviceID ?? "—" }
    var firmware: String { pings.first?.firmware ?? "—" }
    var totalKm: Double { trips.reduce(0) { $0 + $1.summary.distanceKm } }
    var topSpeed: Double { trips.map(\.summary.maxSpeed).max() ?? 0 }
    var lastPing: Date? { pings.last?.date }

    /// v371 exports carry solar voltage at field 23; switching re-reads the loaded file.
    func setBoard(_ newValue: BoardVersion) async {
        guard newValue != board else { return }
        board = newValue
        await reparse()
    }

    func load(url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let text = String(decoding: data, as: UTF8.self)
            fileName = url.lastPathComponent
            rawText = text
            await reparse()
        } catch {
            errorMessage = "File read failed: \(error.localizedDescription)"
        }
    }

    func load(text: String, fileName: String) async {
        self.fileName = fileName
        rawText = text
        await reparse()
    }

    private func reparse() async {
        guard let text = rawText else { return }
        isLoading = true
        defer { isLoading = false }
        let board = self.board
        do {
            let (result, trips) = try await Task.detached(priority: .userInitiated) {
                let result = try PayloadParser.parse(text, board: board)
                return (result, TripDetector.detect(result.pings))
            }.value
            guard !result.pings.isEmpty else {
                errorMessage = "No valid pings found"
                return
            }
            apply(result, trips: trips)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ result: PayloadParser.Result, trips: [Trip]) {
        pings = result.pings
        skipped = result.skipped
        skippedStatusMessages = result.skippedStatusMessages
        self.trips = trips

        var byDate: [String: [Trip]] = [:]
        for t in trips { byDate[t.summary.dateKey, default: []].append(t) }

        // Every calendar day in the raw export gets a tab, even with no qualifying trip,
        // so a parked day shows up with an explanation instead of vanishing.
        var stats: [String: PingStats] = [:]
        for p in result.pings {
            let key = MelbourneTime.dateKey(p.date)
            if byDate[key] == nil { byDate[key] = [] }
            stats[key, default: PingStats()].pings += 1
            if p.hdop >= 90 { stats[key]!.noFix += 1 }
            stats[key]!.maxSpeed = max(stats[key]!.maxSpeed, p.speed)
        }
        tripsByDate = byDate
        statsByDate = stats
        dateKeys = byDate.keys.sorted()
        activeDate = nil
    }

    /// Why the selected date has no trips, mirroring the website's explanation.
    func noTripsExplanation(movingSpeed: Double = TripDetector.Thresholds.standard.movingSpeedKmh) -> String {
        guard let date = activeDate else { return "No trips detected." }
        guard let st = statsByDate[date] else { return "No trips for this date." }
        var reasons: [String] = []
        if st.noFix == st.pings { reasons.append("all pings had no GPS fix (HDOP ≥ 90)") }
        else if st.noFix > 0 { reasons.append("\(st.noFix) of \(st.pings) pings had no GPS fix") }
        if st.maxSpeed < movingSpeed {
            reasons.append(String(format: "max recorded speed was %.1f km/h (below the %.0f km/h movement threshold)", st.maxSpeed, movingSpeed))
        }
        let why = reasons.isEmpty ? "no sustained movement was recorded" : reasons.joined(separator: " · ")
        return "No qualifying trips on this date. \(st.pings) raw ping\(st.pings == 1 ? "" : "s") received: \(why). Device was likely idle or parked."
    }
}
