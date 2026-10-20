import Foundation

/// Talks to the iLinkAir portal API (the backend of login.ilinkair.com.au/tags) to pull
/// High Site payload logs, and rebuilds them as the same "Id,Payload,CreatedDate" CSV the
/// portal's Export button produces, so the result goes through PayloadParser unchanged.
///
/// Endpoints, taken from the portal's Angular bundle:
/// - POST {apiURL}/Account/token  {username, password}  → {data: {access_token, userAccessLevel, …}}
/// - GET  {iotApiURL}/Highsite/ExportIOTHighSitePayloads?From&To[&searchText]
///        → the CSV behind the Logs page's "Export CSV" button (IOTHighSitePayloads_*.csv)
/// - GET  {iotApiURL}/Highsite/GetIOTHighSitePayloads?From=yyyy-MM-dd&To=yyyy-MM-dd[&searchText]&page&pageSize
///        → {data: [{createdDate, payload}], totalRecords}
/// Every authenticated call carries a Bearer token, the user's access-level ids and a JS-style
/// TimezoneOffset header, as the portal's HTTP interceptor does.
struct ILinkAirClient {
    static let apiURL = URL(string: "https://ilinkairassets.azurewebsites.net/api")!
    static let iotApiURL = URL(string: "https://ilinkairiotassets.azurewebsites.net/api")!
    static let pageSize = 1000
    static let maxPages = 500

    struct Session: Equatable {
        var accessToken: String
        var userName: String
        var onSellerId = 0
        var groupId = 0
        var companyId = 0
        var branchId = 0
        var departmentId = 0
    }

    struct PayloadRow: Equatable {
        var createdDate: String
        var payload: String
    }

    struct PayloadPage: Equatable {
        var rows: [PayloadRow]
        var totalRecords: Int?
    }

    enum ClientError: LocalizedError, Equatable {
        case badCredentials(String)
        case unauthorized
        case http(Int, String)
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .badCredentials(let msg): msg.isEmpty ? "The email address or password is incorrect." : msg
            case .unauthorized: "iLinkAir session expired. Sign in again."
            case .http(let code, let body): "iLinkAir returned HTTP \(code)" + (body.isEmpty ? "" : ": \(body)")
            case .badResponse(let what): "Unexpected iLinkAir response: \(what)"
            }
        }
    }

    var urlSession: URLSession = .shared

    // MARK: Requests

    static func loginRequest(username: String, password: String) -> URLRequest {
        var req = URLRequest(url: apiURL.appendingPathComponent("Account/token"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        return req
    }

    static func exportRequest(fromKey: String, toKey: String, searchText: String?,
                              session: Session, now: Date = Date()) -> URLRequest {
        var comps = URLComponents(url: iotApiURL.appendingPathComponent("Highsite/ExportIOTHighSitePayloads"),
                                  resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "From", value: fromKey), URLQueryItem(name: "To", value: toKey)]
        if let s = searchText?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            items.append(URLQueryItem(name: "searchText", value: s))
        }
        comps.queryItems = items
        var req = URLRequest(url: comps.url!)
        req.setValue("text/csv, application/octet-stream, */*", forHTTPHeaderField: "Accept")
        authorize(&req, session: session, now: now)
        return req
    }

    static func payloadsRequest(fromKey: String, toKey: String, searchText: String?, page: Int,
                                pageSize: Int = pageSize, session: Session, now: Date = Date()) -> URLRequest {
        var comps = URLComponents(url: iotApiURL.appendingPathComponent("Highsite/GetIOTHighSitePayloads"),
                                  resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "From", value: fromKey), URLQueryItem(name: "To", value: toKey)]
        if let s = searchText?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            items.append(URLQueryItem(name: "searchText", value: s))
        }
        items.append(URLQueryItem(name: "page", value: String(page)))
        items.append(URLQueryItem(name: "pageSize", value: String(pageSize)))
        comps.queryItems = items
        var req = URLRequest(url: comps.url!)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        authorize(&req, session: session, now: now)
        return req
    }

    static func authorize(_ req: inout URLRequest, session: Session, now: Date = Date()) {
        req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(String(session.onSellerId), forHTTPHeaderField: "OnSellerId")
        req.setValue(String(session.groupId), forHTTPHeaderField: "GroupId")
        req.setValue(String(session.companyId), forHTTPHeaderField: "CompanyId")
        req.setValue(String(session.branchId), forHTTPHeaderField: "BranchId")
        req.setValue(String(session.departmentId), forHTTPHeaderField: "DepartmentId")
        // JavaScript getTimezoneOffset(): minutes *behind* UTC, so Melbourne is -600 / -660.
        let offset = -MelbourneTime.zone.secondsFromGMT(for: now) / 60
        req.setValue(String(offset), forHTTPHeaderField: "TimezoneOffset")
    }

    // MARK: Responses

    static func parseLogin(data: Data, status: Int, username: String) throws -> Session {
        guard (200..<300).contains(status) else {
            let body = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if status == 400 || status == 401 { throw ClientError.badCredentials(body) }
            throw ClientError.http(status, String(body.prefix(200)))
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.badResponse("login body is not JSON")
        }
        let payload = (value(root, "data") as? [String: Any]) ?? root
        guard let token = value(payload, "access_token") as? String ?? value(payload, "accessToken") as? String,
              !token.isEmpty else {
            throw ClientError.badResponse("no access_token in login response")
        }
        var session = Session(accessToken: token, userName: (value(payload, "userName") as? String) ?? username)
        if let level = value(payload, "userAccessLevel") as? [String: Any] {
            session.onSellerId = int(value(level, "onSellerId"))
            session.groupId = int(value(level, "groupId"))
            session.companyId = int(value(level, "companyId"))
            session.branchId = int(value(level, "branchId"))
            session.departmentId = int(value(level, "departmentId"))
        }
        return session
    }

    static func parsePayloadPage(data: Data, status: Int) throws -> PayloadPage {
        if status == 401 { throw ClientError.unauthorized }
        guard (200..<300).contains(status) else {
            throw ClientError.http(status, String(String(decoding: data, as: UTF8.self).prefix(200)))
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            throw ClientError.badResponse("payload page is not JSON")
        }
        let list: [Any]
        var total: Int?
        if let dict = root as? [String: Any] {
            list = (value(dict, "data") as? [Any]) ?? []
            total = value(dict, "totalRecords").map { int($0) }
        } else {
            list = (root as? [Any]) ?? []
        }
        let rows = list.compactMap { item -> PayloadRow? in
            guard let obj = item as? [String: Any], let payload = value(obj, "payload") as? String else { return nil }
            return PayloadRow(createdDate: (value(obj, "createdDate") as? String) ?? "", payload: payload)
        }
        return PayloadPage(rows: rows, totalRecords: total)
    }

    /// Reads the portal's CSV export. Returns nil when the body isn't a CSV with a Payload
    /// column, so the caller can fall back to paging the JSON list.
    static func parseExport(data: Data, status: Int) throws -> [PayloadRow]? {
        if status == 401 { throw ClientError.unauthorized }
        guard (200..<300).contains(status) else { return nil }
        let rows = CSVParser.rows(String(decoding: data, as: UTF8.self))
        guard let header = rows.first?.map({
            $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{FEFF}"))).lowercased()
        }), let p = header.firstIndex(of: "payload") else { return nil }
        let c = header.firstIndex(of: "createddate")
        return rows.dropFirst().compactMap { row in
            guard p < row.count else { return nil }
            return PayloadRow(createdDate: c.flatMap { $0 < row.count ? row[$0] : nil } ?? "", payload: row[p])
        }
    }

    /// Case-insensitive key lookup: ASP.NET may serialise camelCase or PascalCase.
    private static func value(_ dict: [String: Any], _ key: String) -> Any? {
        if let v = dict[key], !(v is NSNull) { return v }
        let lower = key.lowercased()
        return dict.first { $0.key.lowercased() == lower && !($0.value is NSNull) }?.value
    }

    private static func int(_ v: Any?) -> Int {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s) ?? 0 }
        return 0
    }

    // MARK: CSV

    /// Same layout as IOTHighSitePayloads_*.csv: Id, quoted Payload, CreatedDate.
    static func csv(from rows: [PayloadRow]) -> String {
        var out = "Id,Payload,CreatedDate\n"
        for (i, row) in rows.enumerated() {
            out += "\(i),\(quote(row.payload.trimmingCharacters(in: .whitespacesAndNewlines))),\(quote(row.createdDate))\n"
        }
        return out
    }

    private static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// The portal's From/To are plain dates whose time zone isn't documented, so the request
    /// asks for a day either side and this keeps rows whose ping time falls on the chosen
    /// Melbourne dates. Rows without a readable ping time are kept; the parser skips them.
    static func filter(_ rows: [PayloadRow], fromKey: String, toKey: String) -> [PayloadRow] {
        rows.filter { row in
            let parts = row.payload.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count > 10, let date = PayloadParser.parseUTC(String(parts[10])) else { return true }
            let key = MelbourneTime.dateKey(date)
            return key >= fromKey && key <= toKey
        }
    }

    static func paddedKeys(from: Date, to: Date) -> (from: String, to: String) {
        let cal = MelbourneTime.calendar
        let f = cal.date(byAdding: .day, value: -1, to: from) ?? from
        let t = cal.date(byAdding: .day, value: 1, to: to) ?? to
        return (MelbourneTime.dateKey(f), MelbourneTime.dateKey(t))
    }

    // MARK: Calls

    func login(username: String, password: String) async throws -> Session {
        let (data, status) = try await send(Self.loginRequest(username: username, password: password))
        return try Self.parseLogin(data: data, status: status, username: username)
    }

    /// Downloads the portal's CSV export for the Melbourne date range (paging the JSON list if
    /// the export isn't usable) and returns the rows oldest first.
    func fetchPayloads(from: Date, to: Date, searchText: String?, session: Session,
                       progress: @Sendable (Int, Int?) async -> Void = { _, _ in }) async throws -> [PayloadRow] {
        let fromKey = MelbourneTime.dateKey(from), toKey = MelbourneTime.dateKey(to)
        let padded = Self.paddedKeys(from: from, to: to)
        let exportReq = Self.exportRequest(fromKey: padded.from, toKey: padded.to, searchText: searchText, session: session)
        let (exportData, exportStatus) = try await send(exportReq)
        var rows: [PayloadRow]
        if let exported = try Self.parseExport(data: exportData, status: exportStatus) {
            rows = exported
            await progress(rows.count, rows.count)
        } else {
            rows = try await pagePayloads(fromKey: padded.from, toKey: padded.to, searchText: searchText,
                                          session: session, progress: progress)
        }
        let kept = Self.filter(rows, fromKey: fromKey, toKey: toKey)
        return kept.sorted { $0.createdDate < $1.createdDate }
    }

    private func pagePayloads(fromKey: String, toKey: String, searchText: String?, session: Session,
                              progress: @Sendable (Int, Int?) async -> Void) async throws -> [PayloadRow] {
        var rows: [PayloadRow] = []
        var page = 1
        while page <= Self.maxPages {
            try Task.checkCancellation()
            let req = Self.payloadsRequest(fromKey: fromKey, toKey: toKey, searchText: searchText,
                                           page: page, session: session)
            let (data, status) = try await send(req)
            let result = try Self.parsePayloadPage(data: data, status: status)
            rows += result.rows
            await progress(rows.count, result.totalRecords)
            if result.rows.count < Self.pageSize { break }
            if let total = result.totalRecords, rows.count >= total { break }
            page += 1
        }
        return rows
    }

    private func send(_ req: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ClientError.badResponse("not HTTP") }
        return (data, http.statusCode)
    }
}
