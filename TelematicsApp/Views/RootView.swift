import SwiftUI
import UniformTypeIdentifiers

/// Trip list beside the map: a split view on iPad, a push navigation stack on iPhone.
struct RootView: View {
    @Environment(TrackerStore.self) private var store
    @State private var selectedTripID: Trip.ID?
    @State private var showImporter = false
    @State private var showLogic = false
    @State private var showReport = false
    @State private var showAllTrips = false
    @State private var showFetch = false
    @State private var showSaveCSV = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationTitle("AssetIQ - Trip Logger")
                .toolbar { toolbar }
        } detail: {
            if let id = selectedTripID, let trip = store.trips.first(where: { $0.id == id }) {
                TripDetailView(trip: trip)
            } else if store.hasData {
                AllTripsMapView(trips: store.visibleTrips)
            } else {
                ContentUnavailableView("Fetch logs, upload a CSV or select a trip", systemImage: "map",
                                       description: Text("Arrows show heading direction on each ping."))
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
            if case .success(let url) = result {
                selectedTripID = nil
                Task { await store.load(url: url) }
            }
        }
        .sheet(isPresented: $showLogic) { LogicTrackerView() }
        .sheet(isPresented: $showFetch, onDismiss: { if store.isFetched { selectedTripID = nil } }) { ILinkAirFetchView() }
        .fileExporter(isPresented: $showSaveCSV, document: CSVTextDocument(text: store.rawText ?? ""),
                      contentType: .commaSeparatedText, defaultFilename: store.fileName ?? "IOTHighSitePayloads.csv") { result in
            if case .failure(let error) = result { store.errorMessage = "Save failed: \(error.localizedDescription)" }
        }
        .sheet(isPresented: $showReport) { JourneyReportView(trips: store.visibleTrips) }
        .sheet(isPresented: $showAllTrips) {
            NavigationStack {
                AllTripsMapView(trips: store.visibleTrips)
                    .toolbar { Button("Done") { showAllTrips = false } }
            }
        }
        .overlay {
            if store.isLoading {
                ProgressView("Parsing payload data…")
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Couldn't load export", isPresented: .constant(store.errorMessage != nil)) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    // MARK: Sidebar

    @ViewBuilder private var sidebar: some View {
        if !store.hasData {
            VStack(spacing: 20) {
                ContentUnavailableView {
                    VStack(spacing: 12) {
                        AssetIQLogo().frame(width: 96, height: 96)
                        Text("No export loaded")
                    }
                } description: {
                    Text("Fetch High Site logs from iLinkAir for a date range, or import an IOT High Site payload export (Payload + CreatedDate columns). Trips are detected from sustained movement, not just ping timing, so parked GPS jitter and odometer glitches are filtered out.")
                } actions: {
                    Button { showFetch = true } label: { Label("Fetch from iLinkAir", systemImage: "arrow.down.circle") }
                        .buttonStyle(.borderedProminent)
                    Button { showImporter = true } label: { Label("Upload Export CSV", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.bordered)
                }
                boardPicker.padding(.horizontal)
                Text("All times Melbourne AEST/AEDT").font(.caption).foregroundStyle(Theme.yellow)
            }
            .frame(maxHeight: .infinity)
            .background(Theme.bg)
        } else {
            List(selection: $selectedTripID) {
                Section { HeaderStatsView() }
                Section {
                    DateFilterView()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    if store.visibleTrips.isEmpty {
                        Text(store.noTripsExplanation()).font(.callout).foregroundStyle(Theme.muted)
                    }
                    ForEach(store.visibleTrips) { trip in
                        TripCardView(trip: trip).tag(trip.id)
                    }
                } header: {
                    Text("\(store.visibleTrips.count) trips")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
        }
    }

    private var boardPicker: some View {
        Picker("Board", selection: Binding(get: { store.board }, set: { v in Task { await store.setBoard(v) } })) {
            ForEach(BoardVersion.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if store.hasData {
                Button {
                    selectedTripID = nil
                    store.reset()
                } label: { Label("Home", systemImage: "house") }
            } else {
                AssetIQLogo(cornerRadius: 7).frame(width: 30, height: 30)
                    .accessibilityLabel("AssetIQ")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showFetch = true } label: { Label("Fetch from iLinkAir", systemImage: "arrow.down.circle") }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showImporter = true } label: { Label("Upload CSV", systemImage: "square.and.arrow.down") }
        }
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Section("Board") {
                    Picker("Board", selection: Binding(get: { store.board }, set: { v in Task { await store.setBoard(v) } })) {
                        ForEach(BoardVersion.allCases) { Text($0.label).tag($0) }
                    }
                }
                if store.isFetched {
                    Button { showSaveCSV = true } label: { Label("Save CSV", systemImage: "square.and.arrow.up") }
                }
                Button { showAllTrips = true } label: { Label("All Trips Map", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                    .disabled(!store.hasData)
                Button { showReport = true } label: { Label("Journey Report", systemImage: "doc.text") }
                    .disabled(store.visibleTrips.isEmpty)
                Button { showLogic = true } label: { Label("Logic Tracker", systemImage: "info.circle") }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }
}

// MARK: - Header stats

struct HeaderStatsView: View {
    @Environment(TrackerStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("IMEI ").foregroundStyle(Theme.muted) + Text(store.deviceID).foregroundStyle(Theme.accent)
                Spacer()
                Text("FW ").foregroundStyle(Theme.muted) + Text(store.firmware).foregroundStyle(Theme.accent)
            }
            .font(.caption.monospaced())
            Text("Board: \(store.board.label)").font(.caption2).foregroundStyle(Theme.muted)

            HStack {
                stat("\(store.trips.count)", "Trips")
                stat(String(format: "%.0f km", store.totalKm), "Total km")
                stat(String(format: "%.0f km/h", store.topSpeed), "Top Speed")
            }
            if let last = store.lastPing {
                Text("Last ping \(MelbourneTime.shortDate(last)) \(MelbourneTime.time(last)) \(MelbourneTime.abbreviation(last))")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            if let name = store.fileName {
                Text("\(name): \(store.pings.count) pings, \(store.skipped) skipped"
                     + (store.skippedStatusMessages > 0 ? " (\(store.skippedStatusMessages) device-status msgs ignored)" : ""))
                    .font(.caption2).foregroundStyle(Theme.muted).lineLimit(2)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline).foregroundStyle(Theme.accent)
            Text(label).font(.caption2).foregroundStyle(Theme.muted).textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Date filter

struct DateFilterView: View {
    @Environment(TrackerStore.self) private var store

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("All", date: nil, idle: false)
                ForEach(store.dateKeys, id: \.self) { key in
                    let idle = store.tripsByDate[key]?.isEmpty ?? true
                    chip(MelbourneTime.fullDate(key: key) + (idle ? " (0)" : ""), date: key, idle: idle)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func chip(_ label: String, date: String?, idle: Bool) -> some View {
        let active = store.activeDate == date
        return Button { store.activeDate = date } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(active ? Theme.accent : Theme.card, in: Capsule())
                .foregroundStyle(active ? Theme.bg : (idle ? Theme.muted : .primary))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Trip card

struct TripCardView: View {
    let trip: Trip

    var body: some View {
        let s = trip.summary
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("T\(trip.id)").font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                Text(MelbourneTime.fullDate(s.start)).font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                Text(String(format: "HDOP %.1f", s.avgHDOP))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((s.avgHDOP < 2 ? Theme.green : s.avgHDOP < 5 ? Theme.yellow : Theme.red).opacity(0.18), in: Capsule())
                    .foregroundStyle(s.avgHDOP < 2 ? Theme.green : s.avgHDOP < 5 ? Theme.yellow : Theme.red)
            }
            Text("\(MelbourneTime.time(s.start)) → \(MelbourneTime.time(s.end))").font(.subheadline.monospacedDigit())
            HStack {
                stat(String(format: "%.2f", s.distanceKm), "km")
                stat(String(format: "%.0f", s.maxSpeed), "max km/h")
                stat("\(Int(s.durationMin.rounded()))", "min")
                stat("\(s.pingCount)", "pings")
            }
            HStack(spacing: 4) {
                tag("Start", Theme.green)
                if s.dp2Count > 0 { tag("DP2 ×\(s.dp2Count)", Theme.purple) }
                tag("DP3 ×\(s.dp3Count)", Theme.accent)
                s.closedByDP4 ? tag("DP4 ✓", Theme.green) : tag("⚠ Timeout", Theme.yellow)
            }
        }
        .padding(.vertical, 4)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color)
    }
}
