import SwiftUI
import MapKit

enum MapOverlay: String, CaseIterable, Identifiable {
    case speed = "Speed"
    case hdop = "HDOP"
    var id: String { rawValue }
}

/// One trip on the map: route line, a heading arrow (or dot when stationary) per ping
/// coloured by speed or HDOP (DP2 heartbeats get a purple ring), and S/E markers.
struct TripDetailView: View {
    let trip: Trip
    @State private var overlay: MapOverlay = .speed
    @State private var selectedPing: Ping?
    @State private var position: MapCameraPosition = .automatic
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                map
                LegendView(overlay: overlay).padding(10)
            }
            if let ping = selectedPing {
                PingInfoView(ping: ping) { selectedPing = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            TripStatsView(trip: trip)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: selectedPing?.id)
        .sensoryFeedback(.selection, trigger: selectedPing?.id)
        .navigationTitle("Trip \(trip.id) · \(MelbourneTime.shortDate(trip.summary.start))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Colour pings by", selection: $overlay) {
                    ForEach(MapOverlay.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        .onChange(of: trip.id) {
            selectedPing = nil
            position = .automatic
        }
    }

    private var map: some View {
        let pts = trip.pings
        return Map(position: $position) {
            MapPolyline(coordinates: pts.map(\.coordinate))
                .stroke(Theme.dynamic(light: 0x2A3060, dark: 0x8A96D6).opacity(0.8), lineWidth: 3)

            ForEach(Array(pts.dropFirst().dropLast())) { p in
                Annotation("", coordinate: p.coordinate, anchor: .center) {
                    PingMarker(ping: p, color: color(for: p))
                        .id("\(p.id)-\(overlay.rawValue)")
                        .onTapGesture { selectedPing = p }
                        .accessibilityElement()
                        .accessibilityLabel(PingInfoView.summary(p))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { selectedPing = p }
                }
                .annotationTitles(.hidden)
            }

            if let s = pts.first {
                Annotation("Trip Start", coordinate: s.coordinate, anchor: .center) {
                    EndpointMarker(letter: "S", color: Theme.green).onTapGesture { selectedPing = s }
                        .accessibilityLabel("Trip start, " + PingInfoView.summary(s))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { selectedPing = s }
                }
                .annotationTitles(.hidden)
            }
            if let e = pts.last {
                Annotation("Trip End", coordinate: e.coordinate, anchor: .center) {
                    EndpointMarker(letter: "E", color: Theme.red).onTapGesture { selectedPing = e }
                        .accessibilityLabel("Trip end, " + PingInfoView.summary(e))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { selectedPing = e }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
    }

    /// Every ping follows the selected legend. DP2 heartbeats are most pings on v371 boards,
    /// so they are marked with a purple ring (see PingMarker) rather than a purple fill.
    private func color(for p: Ping) -> Color {
        if p.dataPoint == 4 { return Theme.red }
        return overlay == .speed ? Theme.speedColor(p.speed) : Theme.hdopColor(p.hdop)
    }
}

struct PingMarker: View {
    let ping: Ping
    let color: Color

    var body: some View {
        let isDP2 = ping.dataPoint == 2
        ZStack {
            if isDP2 {
                Circle().stroke(Theme.purple, lineWidth: 1.5).frame(width: 18, height: 18)
            }
            if ping.speed > 1 {
                // Arrow points north, rotated to the heading.
                Image(systemName: "location.north.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(color)
                    .shadow(color: .black.opacity(0.6), radius: 1)
                    .rotationEffect(.degrees(ping.direction))
            } else {
                Circle().fill(color.opacity(0.9)).frame(width: 9, height: 9)
            }
        }
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
    }
}

struct EndpointMarker: View {
    let letter: String
    let color: Color

    var body: some View {
        Text(letter)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(color, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
            .frame(width: 32, height: 32)
            .contentShape(Circle())
            .accessibilityElement(children: .ignore)
    }
}

struct LegendView: View {
    let overlay: MapOverlay

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(overlay == .speed ? "Speed (km/h)" : "HDOP Accuracy").font(.caption2.weight(.semibold))
            ForEach(Array((overlay == .speed ? Theme.speedLegend : Theme.hdopLegend).enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    Circle().fill(item.0).frame(width: 8, height: 8)
                    Text(item.1).font(.caption2)
                }
            }
            HStack(spacing: 5) {
                Circle().stroke(Theme.purple, lineWidth: 1.5).frame(width: 8, height: 8)
                Text("DP2 Heartbeat (ring)").font(.caption2)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// Tooltip equivalent: details of the tapped ping.
struct PingInfoView: View {
    let ping: Ping
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(MelbourneTime.shortDate(ping.date)) \(MelbourneTime.time(ping.date)) \(MelbourneTime.abbreviation(ping.date)) (\(MelbourneTime.offsetLabel(ping.date)))")
                    .font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                Text(Theme.dataPointLabel(ping.dataPoint)).font(.caption)
                Text(String(format: "Speed %.1f km/h · Heading %.0f° true N", ping.speed, ping.direction)).font(.caption)
                Text(String(format: "HDOP %.2f (%@) · Elev %.0f m", ping.hdop, Theme.hdopLabel(ping.hdop), ping.elevation)).font(.caption)
                Text(String(format: "Odo %.3f km", Double(ping.odometerM) / 1000)).font(.caption)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close ping details")
            .padding(.top, -10).padding(.trailing, -10)
        }
        .padding(12)
        .background(Theme.card)
    }

    static func summary(_ p: Ping) -> String {
        "\(Theme.dataPointLabel(p.dataPoint)) at \(MelbourneTime.time(p.date)), "
            + String(format: "%.0f kilometres per hour, HDOP %.1f %@", p.speed, p.hdop, Theme.hdopLabel(p.hdop))
    }
}

struct TripStatsView: View {
    let trip: Trip

    var body: some View {
        let s = trip.summary
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                stat("Distance", String(format: "%.2f km", s.distanceKm))
                stat("Duration", MelbourneTime.duration(minutes: s.durationMin.rounded()))
                stat("Max Speed", String(format: "%.1f km/h", s.maxSpeed))
                stat("Avg Speed", String(format: "%.1f km/h", s.avgSpeed))
                stat("Avg HDOP", String(format: "%.2f (%@)", s.avgHDOP, Theme.hdopLabel(s.avgHDOP)))
                stat("Odo End (km)", String(format: "%.1f", Double(s.odometerEndM) / 1000))
                stat("Start (\(MelbourneTime.abbreviation(s.start)))", MelbourneTime.time(s.start))
                stat("End (\(MelbourneTime.abbreviation(s.end)))", MelbourneTime.time(s.end))
                stat("DP2 Heartbeats", "\(s.dp2Count)")
                stat("Trip Close", s.closedByDP4 ? "DP4 end" : "Timeout", color: s.closedByDP4 ? Theme.green : Theme.yellow,
                     symbol: s.closedByDP4 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                if let solar = s.avgSolarMV { stat("Avg Solar", "\(solar) mV") }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.surface)
    }

    private func stat(_ label: String, _ value: String, color: Color = .primary, symbol: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol) }
                Text(value)
            }
            .font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(Theme.muted).textCase(.uppercase)
        }
        .accessibilityElement(children: .combine)
    }
}
