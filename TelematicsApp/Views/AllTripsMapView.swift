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
                            .frame(width: 10, height: 10)
                            .padding(6)
                            .contentShape(Circle())
                            .onTapGesture { selected = trip }
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
                    Button { selected = nil } label: { Image(systemName: "xmark.circle.fill") }
                }
                .padding(12)
                .background(Theme.card)
            }
        }
        .navigationTitle("All Trips")
        .navigationBarTitleDisplayMode(.inline)
    }
}
