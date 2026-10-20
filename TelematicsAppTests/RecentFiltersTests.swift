import XCTest
@testable import TelematicsApp

/// Recent IMEI / text filters on the iLinkAir fetch screen.
@MainActor
final class RecentFiltersTests: XCTestCase {
    func testAddingKeepsMostRecentFirstWithoutDuplicates() {
        var list: [String] = []
        list = ILinkAirStore.adding(" 352648065204596 ", to: list)
        list = ILinkAirStore.adding("ABC", to: list)
        list = ILinkAirStore.adding("", to: list)
        list = ILinkAirStore.adding("abc", to: list)
        XCTAssertEqual(list, ["abc", "352648065204596"])
    }

    func testAddingCapsTheList() {
        let list = (0..<20).reduce([String]()) { ILinkAirStore.adding("imei\($1)", to: $0, limit: 3) }
        XCTAssertEqual(list, ["imei19", "imei18", "imei17"])
    }

    func testFiltersPersistAcrossLaunches() throws {
        let suite = "RecentFiltersTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ILinkAirStore(defaults: defaults)
        store.rememberFilter("111")
        store.rememberFilter("222")
        store.forgetFilter("111")
        store.rememberFilter("333")
        XCTAssertEqual(ILinkAirStore(defaults: defaults).recentFilters, ["333", "222"])

        store.clearRecentFilters()
        XCTAssertEqual(ILinkAirStore(defaults: defaults).recentFilters, [])
    }
}
