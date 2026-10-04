import XCTest
@testable import TelematicsApp

/// Expected values were produced by running the web dashboard's own JavaScript
/// (parsePayloads + detectTrips) on Fixtures/sample_export.csv, so the iOS port must match it.
final class TripDetectionTests: XCTestCase {
    private func fixture() throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sample_export", withExtension: "csv"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testParsesFixtureLikeWebsite() throws {
        let result = try PayloadParser.parse(fixture(), board: .v370)
        XCTAssertEqual(result.pings.count, 50)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(result.skippedStatusMessages, 1)
        XCTAssertEqual(result.pings.first?.deviceID, "352648065204596")
        XCTAssertEqual(result.pings.first?.firmware, "FW1.2")
        XCTAssertNil(result.pings.first?.solarMV)
    }

    func testDetectsTripsLikeWebsite() throws {
        let pings = try PayloadParser.parse(fixture(), board: .v370).pings
        let trips = TripDetector.detect(pings)

        // T3 is a single noisy ping and is discarded, so ids skip it, as on the website.
        XCTAssertEqual(trips.map(\.id), [1, 2, 4, 5])
        XCTAssertEqual(trips.map(\.summary.pingCount), [12, 19, 6, 7])
        XCTAssertEqual(trips.map(\.summary.distanceKm), [6.67, 8.33, 5, 5])
        XCTAssertEqual(trips.map(\.summary.durationMin), [11, 24, 5, 6])
        XCTAssertEqual(trips.map(\.summary.maxSpeed), [40, 50, 60, 60])
        XCTAssertEqual(trips.map(\.summary.dp2Count), [1, 0, 0, 0])
        XCTAssertEqual(trips.map(\.summary.dp3Count), [10, 19, 6, 6])
        XCTAssertEqual(trips.map(\.summary.closedByDP4), [true, false, false, true])
        XCTAssertEqual(trips.map(\.summary.odometerEndM), [106670, 5115833, 5121833, 5127833])
        XCTAssertEqual(trips.map(\.summary.avgHDOP), [1.2, 1.2, 1.2, 1.2])
        XCTAssertEqual(trips.first?.summary.dateKey, "2026-10-01")
    }

    func testStatusMessageIsRejected() throws {
        let csv = "Payload\n\"H0,H1,H2,H3,IMEI,x,x,x,x,x,26-10-01 00:30:00,-37.8,144.9,FW,x,1.0.0,11,0697,153000,km,-,3864886/23_5,Undefined,\""
        let result = try PayloadParser.parse(csv, board: .v370)
        XCTAssertTrue(result.pings.isEmpty)
        XCTAssertEqual(result.skippedStatusMessages, 1)
    }

    func testMissingPayloadColumnThrows() {
        XCTAssertThrowsError(try PayloadParser.parse("a,b\n1,2", board: .v370))
    }

    func testV371ReadsSolarVoltage() throws {
        let csv = "Payload\n\"H0,H1,H2,H3,IMEI,x,x,x,x,x,26-10-01 00:30:00,-37.8,144.9,FW,x,3,1,40,90,45,1.2,1000,120,4200,\""
        XCTAssertEqual(try PayloadParser.parse(csv, board: .v371).pings.first?.solarMV, 4200)
        XCTAssertNil(try PayloadParser.parse(csv, board: .v370).pings.first?.solarMV)
    }

    func testCSVParserHandlesEscapedQuotes() {
        let rows = CSVParser.rows("a,\"b \"\"q\"\" c\",d\r\n1,2,3\n")
        XCTAssertEqual(rows, [["a", "b \"q\" c", "d"], ["1", "2", "3"]])
    }

    func testMelbourneDaylightSaving() throws {
        // 2026-10-04 is the first Sunday in October: AEDT starts at 02:00 local (16:00 UTC on the 3rd).
        let before = try XCTUnwrap(PayloadParser.parseUTC("26-10-03 15:59:00"))
        let after = try XCTUnwrap(PayloadParser.parseUTC("26-10-03 16:01:00"))
        XCTAssertEqual(MelbourneTime.offsetLabel(before), "UTC+10")
        XCTAssertEqual(MelbourneTime.offsetLabel(after), "UTC+11")
        XCTAssertEqual(MelbourneTime.time(after), "03:01:00")
    }

    func testJourneyCSVQuotesFields() throws {
        let pings = try PayloadParser.parse(fixture(), board: .v370).pings
        let trip = try XCTUnwrap(TripDetector.detect(pings).first)
        var row = JourneyRow(trip: trip)
        row.driver = "Sam \"The Driver\""
        let csv = JourneyReport.csv(rows: [row], defaultAsset: "Ute 1", defaultDriver: "", defaultType: .delivery)
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].hasPrefix("\"T1\",\"Ute 1\",\"1 Oct 2026\",\"10:10:00\""))
        XCTAssertTrue(lines[1].contains("\"Delivery\""))
        XCTAssertTrue(lines[1].contains("\"Sam \"\"The Driver\"\"\""))
        XCTAssertTrue(lines[1].hasSuffix("\"DP4 Clean\""))
    }
}
