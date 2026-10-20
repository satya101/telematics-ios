import SwiftUI
import MapKit

/// Every trip in the current date filter, each in its own colour.
struct AllTripsMapView: View {
    let trips: [Trip]
    @State private var selected: Trip?

    var body: some View {
        Map {
            ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                MapPolyline(coordinates: trip.pings.map(\.coordinate))
                    .stroke(Theme.tripPalette[index % Theme.tripPalette.count].opacity(0.8), lineWidth: 3)
                if let start = trip.pings.first {
                    Annotation("T\(trip.id)", coordinate: start.coordinate, anchor: .center) {
                        Circle()
                            .fill(Theme.tripPalette[index % Theme.tripPalette.count])
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            .padding(10)
                            .contentShape(Circle())
                            .onTapGesture { selected = trip }
                            .accessibilityLabel("Trip \(trip.id), starts \(MelbourneTime.time(start.date))")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { selected = trip }
                    }
                }
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
        .safeAreaInset(edge: .bottom) {
            if let t = selected {
                let s = t.summary
                HStack {
                    Text("Trip \(t.id) · \(MelbourneTime.time(s.start))→\(MelbourneTime.time(s.end)) \(MelbourneTime.abbreviation(s.start)) · \(String(format: "%.1f", s.distanceKm)) km")
                        .font(.caption.monospacedDigit())
                    Spacer()
                    Button { selected = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Theme.muted)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Close trip details")
                }
                .padding(.leading, 12).padding(.vertical, 2)
                .background(.regularMaterial)
            }
        }
        .navigationTitle("All Trips")
        .navigationBarTitleDisplayMode(.inline)
    }
}
