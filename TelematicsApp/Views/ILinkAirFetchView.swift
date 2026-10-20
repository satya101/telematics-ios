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
    @FocusState private var focus: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field { case email, password, filter }

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
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Fetch Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
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
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.04)))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: ilinkair.stage == nil)
            .sensoryFeedback(.error, trigger: ilinkair.errorMessage) { _, new in new != nil }
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
                .focused($focus, equals: .email)
                .submitLabel(.next)
                .onSubmit { focus = .password }
            SecureField("Password", text: $password)
                .textContentType(.password)
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit { if canSignIn { signIn() } }
            Button(action: signIn) {
                Label("Sign in", systemImage: "person.badge.key")
            }
            .disabled(!canSignIn)
        } header: {
            Text("Sign in to iLinkAir")
        } footer: {
            Text("Uses your login.ilinkair.com.au account. Your password is stored only in this device's Keychain.")
        }
    }

    private var canSignIn: Bool { !username.isEmpty && !password.isEmpty && !ilinkair.isWorking }

    private func signIn() {
        focus = nil
        task = Task {
            if await ilinkair.signIn(username: username.trimmingCharacters(in: .whitespaces), password: password) {
                password = ""
            }
        }
    }

    private func startFetch() {
        focus = nil
        task = Task {
            if await ilinkair.fetch(from: fromDate, to: toDate, searchText: searchText, into: tracker) {
                dismiss()
            }
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
                            .font(.footnote.monospaced().weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(minHeight: 32)
                            .background(active ? Theme.accent : Theme.card, in: Capsule())
                            .foregroundStyle(active ? Theme.bg : .primary)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Recent filter \(filter)")
                    .accessibilityAddTraits(active ? .isSelected : [])
                    .accessibilityAction(named: "Remove") { ilinkair.forgetFilter(filter) }
                    .contextMenu {
                        Button("Remove", systemImage: "trash", role: .destructive) { ilinkair.forgetFilter(filter) }
                        Button("Clear all recent", systemImage: "xmark.bin", role: .destructive) { ilinkair.clearRecentFilters() }
                    }
                }
                // A visible way to clear history, not just the press-and-hold menu.
                Button("Clear", role: .destructive) { ilinkair.clearRecentFilters() }
                    .buttonStyle(.borderless)
                    .font(.footnote)
                    .frame(minHeight: 32)
                    .padding(.leading, 4)
                    .accessibilityLabel("Clear recent filters")
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
                Label(ilinkair.savedUsername ?? ilinkair.session?.userName ?? "Signed In", systemImage: "person.crop.circle")
                    .lineLimit(1)
                Spacer()
                Button("Sign Out", role: .destructive) { ilinkair.signOut() }
                    .buttonStyle(.borderless)
                    .disabled(ilinkair.isWorking)
            }
        } header: {
            Text("iLinkAir Account")
        }
        Section {
            DatePicker("From", selection: $fromDate, in: ...toDate, displayedComponents: .date)
            DatePicker("To", selection: $toDate, in: fromDate..., displayedComponents: .date)
            HStack {
                TextField("IMEI or text (optional)", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .filter)
                    .submitLabel(.search)
                    .onSubmit { if !ilinkair.isWorking { startFetch() } }
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.muted)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, -10)
                    .accessibilityLabel("Clear filter")
                }
            }
            if !ilinkair.recentFilters.isEmpty {
                recentFilterChips
            }
        } header: {
            Text("Date range (Melbourne)")
        } footer: {
            Text("Leave the filter blank to get every High Site log in the range. Tap a recent filter to use it again.")
        }
        .environment(\.timeZone, MelbourneTime.zone)
        .environment(\.calendar, MelbourneTime.calendar)
        Section {
            Button(action: startFetch) {
                Label("Fetch Logs", systemImage: "arrow.down.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
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
