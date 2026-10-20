import Foundation
import Observation

/// iLinkAir sign-in and log fetching. The token lives in memory only; the username and
/// password live in the Keychain so an expired session can sign in again by itself.
@MainActor
@Observable
final class ILinkAirStore {
    private(set) var session: ILinkAirClient.Session?
    private(set) var savedUsername: String?
    private(set) var isWorking = false
    private(set) var status: String?
    var errorMessage: String?

    private let client: ILinkAirClient

    init(client: ILinkAirClient = ILinkAirClient()) {
        self.client = client
        savedUsername = ILinkAirCredentials.load()?.username
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

    /// Downloads the High Site logs for the Melbourne date range and loads them into the tracker
    /// exactly like an uploaded CSV.
    func fetch(from: Date, to: Date, searchText: String, into tracker: TrackerStore) async -> Bool {
        isWorking = true
        defer { isWorking = false; status = nil }
        do {
            let rows: [ILinkAirClient.PayloadRow]
            do {
                rows = try await fetchRows(from: from, to: to, searchText: searchText, session: try await currentSession())
            } catch ILinkAirClient.ClientError.unauthorized {
                session = nil
                rows = try await fetchRows(from: from, to: to, searchText: searchText, session: try await currentSession())
            }
            guard !rows.isEmpty else {
                errorMessage = "No High Site logs between \(MelbourneTime.fullDate(from)) and \(MelbourneTime.fullDate(to))."
                return false
            }
            status = "Parsing \(rows.count) logs…"
            let name = "IOTHighSitePayloads_\(MelbourneTime.dateKey(from))_to_\(MelbourneTime.dateKey(to)).csv"
            await tracker.load(text: ILinkAirClient.csv(from: rows), fileName: name, fetched: true)
            errorMessage = nil
            return tracker.errorMessage == nil
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func fetchRows(from: Date, to: Date, searchText: String,
                           session: ILinkAirClient.Session) async throws -> [ILinkAirClient.PayloadRow] {
        status = "Exporting logs…"
        return try await client.fetchPayloads(from: from, to: to, searchText: searchText, session: session) { got, total in
            await MainActor.run {
                self.status = total.map { "Fetched \(got) of \($0) logs…" } ?? "Fetched \(got) logs…"
            }
        }
    }

    private func currentSession() async throws -> ILinkAirClient.Session {
        if let session { return session }
        guard let creds = ILinkAirCredentials.load() else { throw ILinkAirClient.ClientError.unauthorized }
        status = "Signing in…"
        let s = try await client.login(username: creds.username, password: creds.password)
        session = s
        return s
    }
}
