import Foundation
import Observation

/// iLinkAir sign-in and log fetching. The token lives in memory only; the username and
/// password live in the Keychain so an expired session can sign in again by itself.
@MainActor
@Observable
final class ILinkAirStore {
    /// Steps of a fetch, in order, for the loading screen.
    enum FetchStage: Int, CaseIterable, Comparable {
        case signingIn, exporting, parsing

        var title: String {
            switch self {
            case .signingIn: "Signing in"
            case .exporting: "Exporting logs"
            case .parsing: "Detecting trips"
            }
        }

        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    private(set) var session: ILinkAirClient.Session?
    private(set) var savedUsername: String?
    private(set) var isWorking = false
    private(set) var status: String?
    private(set) var stage: FetchStage?
    private(set) var fetchedCount = 0
    private(set) var expectedCount: Int?
    private(set) var recentFilters: [String]
    var errorMessage: String?

    private let client: ILinkAirClient
    private let defaults: UserDefaults
    private static let recentFiltersKey = "ilinkair.recentFilters"
    static let recentFiltersLimit = 8

    init(client: ILinkAirClient = ILinkAirClient(), defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        savedUsername = ILinkAirCredentials.load()?.username
        recentFilters = defaults.stringArray(forKey: Self.recentFiltersKey) ?? []
    }

    var isSignedIn: Bool { session != nil || savedUsername != nil }

    func signIn(username: String, password: String) async -> Bool {
        isWorking = true
        status = "Signing in…"
        defer { isWorking = false; status = nil }
        do {
            session = try await client.login(username: username, password: password)
            ILinkAirCredentials.save(.init(username: username, password: password))
            savedUsername = username
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func signOut() {
        session = nil
        savedUsername = nil
        ILinkAirCredentials.delete()
    }

    // MARK: Recent IMEI / text filters

    /// Most recent first, no duplicates (case-insensitive), capped at `limit`.
    static func adding(_ filter: String, to list: [String], limit: Int = recentFiltersLimit) -> [String] {
        let f = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty else { return list }
        return Array(([f] + list.filter { $0.caseInsensitiveCompare(f) != .orderedSame }).prefix(limit))
    }

    func rememberFilter(_ filter: String) {
        recentFilters = Self.adding(filter, to: recentFilters)
        defaults.set(recentFilters, forKey: Self.recentFiltersKey)
    }

    func forgetFilter(_ filter: String) {
        recentFilters.removeAll { $0 == filter }
        defaults.set(recentFilters, forKey: Self.recentFiltersKey)
    }

    func clearRecentFilters() {
        recentFilters = []
        defaults.removeObject(forKey: Self.recentFiltersKey)
    }

    // MARK: Fetch

    /// Downloads the High Site logs for the Melbourne date range and loads them into the tracker
    /// exactly like an uploaded CSV.
    func fetch(from: Date, to: Date, searchText: String, into tracker: TrackerStore) async -> Bool {
        isWorking = true
        fetchedCount = 0
        expectedCount = nil
        rememberFilter(searchText)
        defer { isWorking = false; status = nil; stage = nil }
        do {
            let rows: [ILinkAirClient.PayloadRow]
            do {
                rows = try await fetchRows(from: from, to: to, searchText: searchText, session: try await currentSession())
            } catch ILinkAirClient.ClientError.unauthorized {
                session = nil
                rows = try await fetchRows(from: from, to: to, searchText: searchText, session: try await currentSession())
            }
            try Task.checkCancellation()
            guard !rows.isEmpty else {
                errorMessage = "No High Site logs between \(MelbourneTime.fullDate(from)) and \(MelbourneTime.fullDate(to))."
                return false
            }
            stage = .parsing
            status = "Parsing \(rows.count) logs…"
            let name = "IOTHighSitePayloads_\(MelbourneTime.dateKey(from))_to_\(MelbourneTime.dateKey(to)).csv"
            await tracker.load(text: ILinkAirClient.csv(from: rows), fileName: name, fetched: true)
            errorMessage = nil
            return tracker.errorMessage == nil
        } catch is CancellationError {
            return false
        } catch let error as URLError where error.code == .cancelled {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func fetchRows(from: Date, to: Date, searchText: String,
                           session: ILinkAirClient.Session) async throws -> [ILinkAirClient.PayloadRow] {
        stage = .exporting
        status = "Exporting logs…"
        return try await client.fetchPayloads(from: from, to: to, searchText: searchText, session: session) { got, total in
            await MainActor.run {
                self.fetchedCount = got
                self.expectedCount = total
                self.status = total.map { "Fetched \(got) of \($0) logs…" } ?? "Fetched \(got) logs…"
            }
        }
    }

    private func currentSession() async throws -> ILinkAirClient.Session {
        if let session { return session }
        guard let creds = ILinkAirCredentials.load() else { throw ILinkAirClient.ClientError.unauthorized }
        stage = .signingIn
        status = "Signing in…"
        let s = try await client.login(username: creds.username, password: creds.password)
        session = s
        return s
    }
}
