import XCTest
@testable import TelematicsApp

/// Request building and response parsing for the iLinkAir API, using canned responses
/// shaped like the portal's (see ILinkAirClient for where the shapes come from).
final class ILinkAirClientTests: XCTestCase {
    private let session = ILinkAirClient.Session(accessToken: "tok123", userName: "a@b.com",
                                                 onSellerId: 5, groupId: 6, companyId: 7, branchId: 0, departmentId: 0)

    private func payload(_ utc: String, dp: Int = 3, speed: Double = 50) -> String {
        "H0,H1,H2,H3,352648065204596,x5,x6,x7,x8,x9,\(utc),-37.800000,144.900000,FW1.2,x14,\(dp),1,\(speed),90,45,1.2,100000,120,"
    }

    // MARK: Requests

    func testLoginRequest() throws {
        let req = ILinkAirClient.loginRequest(username: "a@b.com", password: "p\"w")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.absoluteString, "https://ilinkairassets.azurewebsites.net/api/Account/token")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(req.httpBody)) as? [String: String])
        XCTAssertEqual(body, ["username": "a@b.com", "password": "p\"w"])
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    }

    func testPayloadsRequest() throws {
        let winter = ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!
        let req = ILinkAirClient.payloadsRequest(fromKey: "2026-06-30", toKey: "2026-07-02", searchText: " 3526 ",
                                                 page: 2, pageSize: 1000, session: session, now: winter)
        let comps = try XCTUnwrap(URLComponents(url: XCTUnwrap(req.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.host, "ilinkairiotassets.azurewebsites.net")
        XCTAssertEqual(comps.path, "/api/Highsite/GetIOTHighSitePayloads")
        XCTAssertEqual(comps.queryItems, [
            URLQueryItem(name: "From", value: "2026-06-30"), URLQueryItem(name: "To", value: "2026-07-02"),
            URLQueryItem(name: "searchText", value: "3526"),
            URLQueryItem(name: "page", value: "2"), URLQueryItem(name: "pageSize", value: "1000"),
        ])
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok123")
        XCTAssertEqual(req.value(forHTTPHeaderField: "OnSellerId"), "5")
        XCTAssertEqual(req.value(forHTTPHeaderField: "GroupId"), "6")
        XCTAssertEqual(req.value(forHTTPHeaderField: "CompanyId"), "7")
        XCTAssertEqual(req.value(forHTTPHeaderField: "BranchId"), "0")
        XCTAssertEqual(req.value(forHTTPHeaderField: "TimezoneOffset"), "-600")   // AEST

        let summer = ISO8601DateFormatter().date(from: "2026-12-01T00:00:00Z")!
        let req2 = ILinkAirClient.payloadsRequest(fromKey: "a", toKey: "b", searchText: "", page: 1,
                                                  session: session, now: summer)
        XCTAssertEqual(req2.value(forHTTPHeaderField: "TimezoneOffset"), "-660")  // AEDT
        XCTAssertFalse(req2.url!.absoluteString.contains("searchText"))
    }

    func testExportRequest() throws {
        let req = ILinkAirClient.exportRequest(fromKey: "2026-09-30", toKey: "2026-10-02", searchText: nil, session: session)
        let comps = try XCTUnwrap(URLComponents(url: XCTUnwrap(req.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.host, "ilinkairiotassets.azurewebsites.net")
        XCTAssertEqual(comps.path, "/api/Highsite/ExportIOTHighSitePayloads")
        XCTAssertEqual(comps.queryItems, [URLQueryItem(name: "From", value: "2026-09-30"),
                                          URLQueryItem(name: "To", value: "2026-10-02")])
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok123")
    }

    func testParseExport() throws {
        let csv = "\u{FEFF}Id,Payload,CreatedDate\n7,\"A,B,C\",2026-10-01T00:00:05\n8,\"D\"\n"
        let rows = try XCTUnwrap(ILinkAirClient.parseExport(data: Data(csv.utf8), status: 200))
        XCTAssertEqual(rows, [.init(createdDate: "2026-10-01T00:00:05", payload: "A,B,C"), .init(createdDate: "", payload: "D")])
        XCTAssertNil(try ILinkAirClient.parseExport(data: Data("Id,Message\n1,x".utf8), status: 200))
        XCTAssertNil(try ILinkAirClient.parseExport(data: Data(), status: 404))
        XCTAssertThrowsError(try ILinkAirClient.parseExport(data: Data(), status: 401))
    }

    func testPaddedKeysCoverDayEitherSide() {
        let cal = MelbourneTime.calendar
        let from = cal.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let to = cal.date(from: DateComponents(year: 2026, month: 10, day: 3))!
        let keys = ILinkAirClient.paddedKeys(from: from, to: to)
        XCTAssertEqual(keys.from, "2026-09-30")
        XCTAssertEqual(keys.to, "2026-10-04")
    }

    // MARK: Responses

    func testParseLogin() throws {
        let json = """
        {"data":{"access_token":"abc","userName":"a@b.com","firstName":"R","userAccessLevel":{"onSellerId":11,"groupId":"22","companyId":33,"branchId":null}},"success":true}
        """
        let s = try ILinkAirClient.parseLogin(data: Data(json.utf8), status: 200, username: "typed")
        XCTAssertEqual(s, .init(accessToken: "abc", userName: "a@b.com", onSellerId: 11, groupId: 22, companyId: 33))
    }

    func testParseLoginPascalCaseWithoutAccessLevel() throws {
        let json = #"{"Data":{"Access_Token":"xyz"}}"#
        let s = try ILinkAirClient.parseLogin(data: Data(json.utf8), status: 200, username: "typed")
        XCTAssertEqual(s, .init(accessToken: "xyz", userName: "typed"))
    }

    func testParseLoginBadPassword() {
        let body = Data("The email address or password is incorrect. Please retry...".utf8)
        XCTAssertThrowsError(try ILinkAirClient.parseLogin(data: body, status: 401, username: "x")) { error in
            XCTAssertEqual(error as? ILinkAirClient.ClientError,
                           .badCredentials("The email address or password is incorrect. Please retry..."))
        }
        XCTAssertThrowsError(try ILinkAirClient.parseLogin(data: Data(#"{"data":{}}"#.utf8), status: 200, username: "x"))
    }

    func testParsePayloadPage() throws {
        let json = """
        {"data":[{"id":1,"createdDate":"2026-10-01T10:00:00","payload":"A,B"},{"id":2,"createdDate":null,"payload":"C"},{"id":3}],"totalRecords":2500}
        """
        let page = try ILinkAirClient.parsePayloadPage(data: Data(json.utf8), status: 200)
        XCTAssertEqual(page.totalRecords, 2500)
        XCTAssertEqual(page.rows, [.init(createdDate: "2026-10-01T10:00:00", payload: "A,B"),
                                   .init(createdDate: "", payload: "C")])
        XCTAssertThrowsError(try ILinkAirClient.parsePayloadPage(data: Data(), status: 401)) { error in
            XCTAssertEqual(error as? ILinkAirClient.ClientError, .unauthorized)
        }
    }

    // MARK: CSV

    func testCSVRoundTripsThroughPayloadParser() throws {
        let rows = [
            ILinkAirClient.PayloadRow(createdDate: "2026-10-01T00:00:05", payload: payload("26-10-01 00:00:00") + "\r\n"),
            ILinkAirClient.PayloadRow(createdDate: "2026-10-01T00:10:05", payload: payload("26-10-01 00:10:00", dp: 2)),
            ILinkAirClient.PayloadRow(createdDate: "2026-10-01T00:11:00", payload: "status \"quoted\",1.0.0"),
        ]
        let csv = ILinkAirClient.csv(from: rows)
        XCTAssertTrue(csv.hasPrefix("Id,Payload,CreatedDate\n0,\"H0,H1,"))
        let parsed = CSVParser.rows(csv)
        XCTAssertEqual(parsed.count, 4)
        XCTAssertEqual(parsed[3][1], "status \"quoted\",1.0.0")

        let result = try PayloadParser.parse(csv, board: .v370)
        XCTAssertEqual(result.pings.count, 2)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(result.pings.map(\.dataPoint), [3, 2])
        XCTAssertEqual(result.pings.first?.deviceID, "352648065204596")
    }

    func testFilterKeepsMelbourneDates() {
        // 13:59 UTC on 30 Sep is 23:59 AEST (out); 14:00 UTC is 00:00 on 1 Oct (in).
        // 1 Oct 13:00 UTC is 23:00 AEST, still 1 Oct (in); 2 Oct 14:00 UTC is 3 Oct 00:00 AEST (out).
        let rows = ["26-09-30 13:59:00", "26-09-30 14:00:00", "26-10-01 13:00:00", "26-10-02 14:00:00"]
            .map { ILinkAirClient.PayloadRow(createdDate: "", payload: payload($0)) }
            + [ILinkAirClient.PayloadRow(createdDate: "", payload: "short,status")]
        let kept = ILinkAirClient.filter(rows, fromKey: "2026-10-01", toKey: "2026-10-02")
        XCTAssertEqual(kept, [rows[1], rows[2], rows[4]])
    }

    // MARK: Paging

    func testFetchUsesExportCSV() async throws {
        let csv = ILinkAirClient.csv(from: [
            .init(createdDate: "2026-10-01T12:00:00", payload: payload("26-10-01 02:00:00")),
            .init(createdDate: "2026-09-30T12:00:00", payload: payload("26-09-30 02:00:00")),
        ])
        StubProtocol.export = Data(csv.utf8)
        StubProtocol.pages = [:]
        StubProtocol.requested = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let client = ILinkAirClient(urlSession: URLSession(configuration: config))

        let day = MelbourneTime.calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let rows = try await client.fetchPayloads(from: day, to: day, searchText: nil, session: session)
        XCTAssertEqual(StubProtocol.requested, [-1])               // export only, no paging
        XCTAssertEqual(rows.map(\.createdDate), ["2026-10-01T12:00:00"])
    }

    func testFetchFallsBackToPagingAndFilters() async throws {
        StubProtocol.export = nil
        let first = (0..<ILinkAirClient.pageSize).map { i in
            ["createdDate": String(format: "2026-10-01T%02d:%02d:00", (i / 60) % 24, i % 60),
             "payload": payload("26-10-01 02:00:00")]
        }
        let second = [["createdDate": "2026-10-05T00:00:00", "payload": payload("26-10-05 02:00:00")],
                      ["createdDate": "2026-10-01T23:59:59", "payload": payload("26-10-01 03:00:00")]]
        StubProtocol.pages = [
            1: try JSONSerialization.data(withJSONObject: ["data": first, "totalRecords": first.count + 2]),
            2: try JSONSerialization.data(withJSONObject: ["data": second, "totalRecords": first.count + 2]),
        ]
        StubProtocol.requested = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let client = ILinkAirClient(urlSession: URLSession(configuration: config))

        let day = MelbourneTime.calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let rows = try await client.fetchPayloads(from: day, to: day, searchText: nil, session: session)

        XCTAssertEqual(StubProtocol.requested, [-1, 1, 2])
        XCTAssertEqual(rows.count, ILinkAirClient.pageSize + 1)   // 5 Oct row dropped
        XCTAssertEqual(rows.last?.createdDate, "2026-10-01T23:59:59")
    }
}

/// Serves the canned export (logged as page -1, 404 when nil) and GetIOTHighSitePayloads pages.
private final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var export: Data?
    nonisolated(unsafe) static var pages: [Int: Data] = [:]
    nonisolated(unsafe) static var requested: [Int] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let isExport = request.url!.path.hasSuffix("ExportIOTHighSitePayloads")
        let page = isExport ? -1 : Int(comps?.queryItems?.first { $0.name == "page" }?.value ?? "") ?? 0
        Self.requested.append(page)
        let ok = request.value(forHTTPHeaderField: "Authorization") == "Bearer tok123"
        let code = !ok ? 401 : (isExport && Self.export == nil ? 404 : 200)
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = isExport ? (Self.export ?? Data()) : (Self.pages[page] ?? Data(#"{"data":[]}"#.utf8))
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
