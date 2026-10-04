import XCTest
@testable import TelematicsApp

/// Real v371 export (IOTHighSitePayloads_2026-10-02, IMEI 868531065602331) checked trip by trip
/// against the web dashboard. sample_v371_expected.json is the website's own parsePayloads +
/// detectTrips output for this file with the Board toggle set to v371.
final class SampleExportV371Tests: XCTestCase {
    private struct Expected: Decodable {
        struct TripRow: Decodable {
            let id: Int, pts: Int, dist: Double, dur: Double, max: Double, avg: Double, hdop: Double
            let dp2: Int, dp3: Int, dp4: Bool, odo: Int, solar: Int?, date: String, startUtc: String
        }
        let records: Int, skipped: Int, skippedStatusMsg: Int
        let trips: [TripRow]
    }

    private func load(_ name: String, _ ext: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: ext))
        return try Data(contentsOf: url)
    }

    func testMatchesWebsiteTripByTrip() throws {
        let csv = String(decoding: try load("sample_v371", "csv"), as: UTF8.self)
        let expected = try JSONDecoder().decode(Expected.self, from: try load("sample_v371_expected", "json"))

        let parsed = try PayloadParser.parse(csv, board: .v371)
        XCTAssertEqual(parsed.pings.count, expected.records)
        XCTAssertEqual(parsed.skipped, expected.skipped)
        XCTAssertEqual(parsed.skippedStatusMessages, expected.skippedStatusMsg)

        let trips = TripDetector.detect(parsed.pings)
        XCTAssertEqual(trips.map(\.id), expected.trips.map(\.id))

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for (trip, exp) in zip(trips, expected.trips) {
            let s = trip.summary
            let label = "T\(exp.id)"
            XCTAssertEqual(s.pingCount, exp.pts, label)
            XCTAssertEqual(s.distanceKm, exp.dist, accuracy: 0.0001, label)
            XCTAssertEqual(s.durationMin, exp.dur, accuracy: 0.0001, label)
            XCTAssertEqual(s.maxSpeed, exp.max, accuracy: 0.0001, label)
            XCTAssertEqual(s.avgSpeed, exp.avg, accuracy: 0.0001, label)
            XCTAssertEqual(s.avgHDOP, exp.hdop, accuracy: 0.0001, label)
            XCTAssertEqual(s.dp2Count, exp.dp2, label)
            XCTAssertEqual(s.dp3Count, exp.dp3, label)
            XCTAssertEqual(s.closedByDP4, exp.dp4, label)
            XCTAssertEqual(s.odometerEndM, exp.odo, label)
            XCTAssertEqual(s.avgSolarMV, exp.solar, label)
            XCTAssertEqual(s.dateKey, exp.date, label)
            XCTAssertEqual(s.start, iso.date(from: exp.startUtc), label)
        }
    }

    func testV370ReadingIgnoresSolar() throws {
        let csv = String(decoding: try load("sample_v371", "csv"), as: UTF8.self)
        let trips = TripDetector.detect(try PayloadParser.parse(csv, board: .v370).pings)
        XCTAssertTrue(trips.allSatisfy { $0.summary.avgSolarMV == nil })
    }
}
