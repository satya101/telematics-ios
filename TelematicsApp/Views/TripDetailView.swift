import SwiftUI
import MapKit

enum MapOverlay: String, CaseIterable, Identifiable {
    case speed = "Speed"
    case hdop = "HDOP"
    var id: String { rawValue }
}

/// One trip on the map: route line, a heading arrow (or dot when stationary) per ping
/// coloured by speed or HDOP, purple DP2 heartbeats, and S/E markers.
struct TripDetailView: View {
    let trip: Trip
    @State private var overlay: MapOverlay = .speed
    @State private var selectedPing: Ping?
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                map
                LegendView(overlay: overlay).padding(10)
            }
            if let ping = selectedPing {
                PingInfoView(ping: ping) { selectedPing = nil }
            }
            TripStatsView(trip: trip)
        }
        .navigationTitle("T\(trip.id) · \(MelbourneTime.fullDate(trip.summary.start))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Picker("Overlay", selection: $overlay) {
                ForEach(MapOverlay.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
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
                .stroke(Color(hex: 0x2A3060).opacity(0.8), lineWidth: 3)

            ForEach(Array(pts.dropFirst().dropLast())) { p in
                Annotation("", coordinate: p.coordinate, anchor: .center) {
                    PingMarker(ping: p, color: color(for: p))
                        .onTapGesture { selectedPing = p }
                }
                .annotationTitles(.hidden)
            }

            if let s = pts.first {
                Annotation("Trip Start", coordinate: s.coordinate, anchor: .center) {
                    EndpointMarker(letter: "S", color: Theme.green).onTapGesture { selectedPing = s }
                }
                .annotationTitles(.hidden)
            }
            if let e = pts.last {
                Annotation("Trip End", coordinate: e.coordinate, anchor: .center) {
                    EndpointMarker(letter: "E", color: Theme.red).onTapGesture { selectedPing = e }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
    }

    private func color(for p: Ping) -> Color {
        if p.dataPoint == 4 { return Theme.red }
        if p.dataPoint == 2 { return Theme.purple }
        return overlay == .speed ? Theme.speedColor(p.speed) : Theme.hdopColor(p.hdop)
    }
}

struct PingMarker: View {
    let ping: Ping
    let color: Color

    var body: some View {
        let isDP2 = ping.dataPoint == 2
        if ping.speed > 1 {
            // Arrow points north, rotated to the heading.
            Image(systemName: "location.north.fill")
                .font(.system(size: isDP2 ? 10 : 12))
                .foregroundStyle(color)
                .shadow(color: .black.opacity(0.6), radius: 1)
                .rotationEffect(.degrees(ping.direction))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        } else {
            Circle()
                .fill(color.opacity(isDP2 ? 0.5 : 0.85))
                .frame(width: isDP2 ? 8 : 10, height: isDP2 ? 8 : 10)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
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
                Circle().fill(Theme.purple).frame(width: 8, height: 8)
                Text("DP2 Heartbeat").font(.caption2)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
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
            Button(action: onClose) { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
        }
        .padding(12)
        .background(Theme.card)
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
                stat("Trip Close", s.closedByDP4 ? "DP4 ✓" : "Timeout ⚠", color: s.closedByDP4 ? Theme.green : Theme.yellow)
                if let solar = s.avgSolarMV { stat("Avg Solar", "\(solar) mV") }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.surface)
    }

    private func stat(_ label: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(Theme.muted).textCase(.uppercase)
        }
    }
}
