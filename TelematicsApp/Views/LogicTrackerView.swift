import SwiftUI

/// How trips are detected, as on the web dashboard's Logic Tracker.
struct LogicTrackerView: View {
    @Environment(\.dismiss) private var dismiss
    private let t = TripDetector.Thresholds.standard

    private let fields: [(String, String)] = [
        ("parts[4]", "Device IMEI"),
        ("parts[10]", "Timestamp, UTC, converted to Melbourne AEST/AEDT"),
        ("parts[11], [12]", "Latitude, Longitude"),
        ("parts[13]", "Firmware version"),
        ("parts[15]", "Data Point type: 2 = heartbeat/start, 3 = data, 4 = trip end"),
        ("parts[17]", "Speed (km/h)"),
        ("parts[18]", "Heading (° true north), shown as map arrows"),
        ("parts[20]", "HDOP, GPS fix quality (lower is better; 99.9 = invalid)"),
        ("parts[21]", "Odometer (metres)"),
        ("parts[23]", "v371 boards only: solar panel charging voltage (mV). Set Board to v371 to read it."),
    ]

    var body: some View {
        NavigationStack {
            List {
                step(1, "Payload field reference") {
                    Text("Each CSV row's Payload field is a comma-separated string. The columns used:")
                    ForEach(fields, id: \.0) { f in
                        HStack(alignment: .top) {
                            Text(f.0).font(.caption.monospaced()).foregroundStyle(Theme.accent).frame(width: 96, alignment: .leading)
                            Text(f.1).font(.caption)
                        }
                    }
                }
                step(2, "Why ping timing alone doesn't work") {
                    Text("The device sends a position ping every 30s–50min whether or not the vehicle is moving, and a DP2 heartbeat roughly every 10 minutes during travel. Gaps between pings either merge a parked day into one trip or split one journey into dozens of fragments, so trips are detected from sustained movement instead.")
                }
                step(3, "Opening a trip") {
                    Text("A trip opens when a ping shows speed above the moving threshold (high enough to ignore 0.1–2 km/h parked GPS jitter), or when a DP2 arrives with no trip open.")
                }
                step(4, "Keeping a trip open") {
                    Text("A trip stays open through DP2 heartbeats and DP3 data pings. The stationary clock starts only once speed drops below the moving threshold and resets as soon as movement resumes, so stops at lights don't end the trip.")
                }
                step(5, "Closing a trip") {
                    Text("Whichever comes first: an explicit DP4 trip-end signal (clean close), continuous stationary time over the stationary timeout, or a comms gap longer than the lost-signal timeout.")
                }
                step(6, "Distance & glitch filtering") {
                    Text("Distance is summed only from consecutive odometer deltas whose implied speed is plausible. Odometer counter resets (multi-thousand-km instant jumps, usually with HDOP 99.9) are excluded.")
                }
                step(7, "Discarding non-trips") {
                    Text("A closed trip is dropped if its distance and duration are negligible, which removes phantom trips from a single noisy ping while parked.")
                }
                step(8, "Current thresholds") {
                    threshold("Moving speed", "> \(fmt(t.movingSpeedKmh)) km/h")
                    threshold("Stationary timeout", "\(fmt(t.stationaryTimeoutMin)) min")
                    threshold("Lost-signal timeout", "\(fmt(t.commsGapMin)) min")
                    threshold("Max plausible speed", "\(fmt(t.maxPlausibleKmh)) km/h")
                    threshold("Min trip distance", "\(fmt(t.minTripDistanceKm)) km")
                    threshold("Min trip duration", "\(fmt(t.minTripDurationMin)) min")
                }
            }
            .navigationTitle("Trip Detection Logic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func step<Content: View>(_ n: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        Section {
            content().font(.callout).foregroundStyle(.secondary)
        } header: {
            Label { Text(title) } icon: { Text("\(n)").foregroundStyle(Theme.accent) }
        }
    }

    private func threshold(_ name: String, _ value: String) -> some View {
        HStack { Text(name); Spacer(); Text(value).foregroundStyle(Theme.accent).monospacedDigit() }
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }
}
