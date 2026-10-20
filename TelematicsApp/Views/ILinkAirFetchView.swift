import SwiftUI
import UniformTypeIdentifiers

/// Sign in to iLinkAir and pull High Site payload logs for a Melbourne date range.
struct ILinkAirFetchView: View {
    @Environment(TrackerStore.self) private var tracker
    @Environment(ILinkAirStore.self) private var ilinkair
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var fromDate = MelbourneTime.calendar.startOfDay(for: Date())
    @State private var toDate = MelbourneTime.calendar.startOfDay(for: Date())
    @State private var searchText = ""
    @State private var task: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                if ilinkair.isSignedIn {
                    signedIn
                } else {
                    signInForm
                }
                if let status = ilinkair.status, ilinkair.stage == nil {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(status).foregroundStyle(Theme.muted)
                        }
                    }
                }
                if let error = ilinkair.errorMessage {
                    Section { Text(error).foregroundStyle(Theme.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("iLinkAir High Site Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        task?.cancel()
                        dismiss()
                    }
                }
            }
            .onAppear { ilinkair.errorMessage = nil }
            .overlay {
                if let stage = ilinkair.stage {
                    FetchLoadingView(stage: stage, fetched: ilinkair.fetchedCount, expected: ilinkair.expectedCount,
                                     subtitle: fetchSubtitle) {
                        task?.cancel()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: ilinkair.stage == nil)
            .interactiveDismissDisabled(ilinkair.isWorking)
        }
    }

    private var signInForm: some View {
        Section {
            TextField("Email", text: $username)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textContentType(.password)
            Button {
                task = Task {
                    if await ilinkair.signIn(username: username.trimmingCharacters(in: .whitespaces), password: password) {
                        password = ""
                    }
                }
            } label: {
                Label("Sign in", systemImage: "person.badge.key")
            }
            .disabled(username.isEmpty || password.isEmpty || ilinkair.isWorking)
        } header: {
            Text("Sign in to iLinkAir")
        } footer: {
            Text("Uses your login.ilinkair.com.au account. Your password is stored only in this device's Keychain.")
        }
    }

    private var recentFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath").font(.caption).foregroundStyle(Theme.muted)
                ForEach(ilinkair.recentFilters, id: \.self) { filter in
                    let active = searchText.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(filter) == .orderedSame
                    Button { searchText = active ? "" : filter } label: {
                        Text(filter)
                            .font(.caption.monospaced().weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(active ? Theme.accent : Theme.card, in: Capsule())
                            .foregroundStyle(active ? Theme.bg : .primary)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove", systemImage: "trash", role: .destructive) { ilinkair.forgetFilter(filter) }
                        Button("Clear all recent", systemImage: "xmark.bin", role: .destructive) { ilinkair.clearRecentFilters() }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var fetchSubtitle: String {
        let range = MelbourneTime.fullDate(fromDate) + (MelbourneTime.dateKey(fromDate) == MelbourneTime.dateKey(toDate)
            ? "" : " – " + MelbourneTime.fullDate(toDate))
        let filter = searchText.trimmingCharacters(in: .whitespaces)
        return filter.isEmpty ? range : "\(range) · \(filter)"
    }

    @ViewBuilder private var signedIn: some View {
        Section {
            HStack {
                Label(ilinkair.savedUsername ?? ilinkair.session?.userName ?? "Signed in", systemImage: "person.crop.circle")
                Spacer()
                Button("Sign out", role: .destructive) { ilinkair.signOut() }
                    .disabled(ilinkair.isWorking)
            }
        }
        Section {
            DatePicker("From", selection: $fromDate, in: ...toDate, displayedComponents: .date)
            DatePicker("To", selection: $toDate, in: fromDate..., displayedComponents: .date)
            HStack {
                TextField("Filter (IMEI or text, optional)", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear filter")
                }
            }
            if !ilinkair.recentFilters.isEmpty {
                recentFilterChips
            }
        } header: {
            Text("Date range (Melbourne)")
        } footer: {
            Text("Leave the filter blank to get every High Site log in the range, as on the portal's Logs page. Recent filters are remembered; press and hold one to remove it.")
        }
        .environment(\.timeZone, MelbourneTime.zone)
        .environment(\.calendar, MelbourneTime.calendar)
        Section {
            Button {
                task = Task {
                    if await ilinkair.fetch(from: fromDate, to: toDate, searchText: searchText, into: tracker) {
                        dismiss()
                    }
                }
            } label: {
                Label("Fetch logs", systemImage: "arrow.down.circle")
            }
            .disabled(ilinkair.isWorking)
        }
    }
}

/// Lets the fetched logs be saved with the same columns as a portal export.
struct CSVTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
