import Foundation

/// Smart trip detection (v4), ported from the web dashboard.
///
/// Trips are bounded by sustained movement, not ping gaps: the device pings every
/// 30s-50min even while parked (with 0.1-2 km/h GPS jitter) and sends DP2 heartbeats
/// roughly every 10 min while driving, so gap-based splitting either merges a parked
/// day into one trip or fragments one drive into many.
enum TripDetector {
    struct Thresholds {
        var movingSpeedKmh = 5.0          // above this = genuine driving, not jitter
        var stationaryTimeoutMin = 12.0   // close after this long continuously non-moving
        var commsGapMin = 30.0            // force-close if no ping at all for this long
        var maxPlausibleKmh = 160.0       // odometer deltas implying more are glitches
        var minTripDistanceKm = 0.3       // discard jitter-only trips shorter than this
        var minTripDurationMin = 1.5      // discard trips briefer than this

        static let standard = Thresholds()
    }

    static func detect(_ pings: [Ping], thresholds t: Thresholds = .standard) -> [Trip] {
        var raw: [(id: Int, pings: [Ping], closedByDP4: Bool)] = []
        var current: (id: Int, pings: [Ping])?
        var idleSince: Date?
        var nextID = 0

        func close(byDP4: Bool) {
            guard let c = current else { return }
            raw.append((c.id, c.pings, byDP4))
            current = nil
            idleSince = nil
        }

        func open(with p: Ping) {
            nextID += 1
            current = (nextID, [p])
        }

        for (i, r) in pings.enumerated() {
            let gapMin = i > 0 ? r.date.timeIntervalSince(pings[i - 1].date) / 60 : 0
            let isMoving = r.speed > t.movingSpeedKmh

            // Lost comms for too long: force close whatever was open.
            if current != nil && gapMin > t.commsGapMin { close(byDP4: false) }

            // Sustained-stationary timeout for the open trip.
            if current != nil {
                if isMoving {
                    idleSince = nil
                } else if let since = idleSince {
                    if r.date.timeIntervalSince(since) / 60 > t.stationaryTimeoutMin { close(byDP4: false) }
                } else {
                    idleSince = r.date
                }
            }

            switch r.dataPoint {
            case DataPoint.tripEnd.rawValue:
                // Explicit trip end always closes immediately.
                if current != nil {
                    current!.pings.append(r)
                    close(byDP4: true)
                }
            case DataPoint.heartbeat.rawValue:
                // Heartbeat if a trip is open, tentative open otherwise.
                if current == nil {
                    open(with: r)
                    idleSince = isMoving ? nil : r.date
                } else {
                    current!.pings.append(r)
                }
            case DataPoint.data.rawValue:
                // Accumulate if open, or open fresh on genuine movement.
                if current != nil {
                    current!.pings.append(r)
                } else if isMoving {
                    open(with: r)
                    idleSince = nil
                }
            default:
                break
            }
        }
        close(byDP4: false)

        // Summarise, then drop trips that are just GPS jitter.
        return raw.compactMap { trip in
            let s = summarize(trip.pings, closedByDP4: trip.closedByDP4, maxPlausibleKmh: t.maxPlausibleKmh)
            guard s.distanceKm >= t.minTripDistanceKm,
                  s.durationMin >= t.minTripDurationMin,
                  s.pingCount > 2 else { return nil }
            return Trip(id: trip.id, pings: trip.pings, summary: s)
        }
    }

    /// Sum of consecutive odometer deltas whose implied speed is physically plausible.
    /// Rejects counter resets (multi-thousand-km instant jumps, usually with HDOP 99.9).
    static func plausibleDistanceKm(_ pts: [Ping], maxKmh: Double = Thresholds.standard.maxPlausibleKmh) -> Double {
        guard pts.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<pts.count {
            let dtHr = pts[i].date.timeIntervalSince(pts[i - 1].date) / 3600
            let dKm = Double(pts[i].odometerM - pts[i - 1].odometerM) / 1000
            if dKm < 0 { continue }
            if dtHr > 0 && dKm / dtHr > maxKmh { continue }
            total += dKm
        }
        return total
    }

    static func summarize(_ pts: [Ping], closedByDP4: Bool, maxPlausibleKmh: Double = Thresholds.standard.maxPlausibleKmh) -> TripSummary {
        var maxSpeed = 0.0, speedSum = 0.0, speedCount = 0
        var hdopSum = 0.0, hdopCount = 0
        var maxOdo = Int.min
        var solarSum = 0.0, solarCount = 0
        var dp2 = 0, dp3 = 0

        for p in pts {
            maxOdo = max(maxOdo, p.odometerM)
            if p.hdop < 99 {
                hdopSum += p.hdop; hdopCount += 1
                if p.speed > 0 {
                    speedSum += p.speed; speedCount += 1
                    maxSpeed = max(maxSpeed, p.speed)
                }
            }
            if let s = p.solarMV { solarSum += s; solarCount += 1 }
            if p.dataPoint == 2 { dp2 += 1 }
            if p.dataPoint == 3 { dp3 += 1 }
        }

        let start = pts.first!.date, end = pts.last!.date
        func round(_ v: Double, _ places: Double) -> Double { (v * places).rounded() / places }

        return TripSummary(
            dateKey: MelbourneTime.dateKey(start),
            start: start,
            end: end,
            durationMin: round(end.timeIntervalSince(start) / 60, 10),
            distanceKm: round(plausibleDistanceKm(pts, maxKmh: maxPlausibleKmh), 100),
            maxSpeed: round(maxSpeed, 10),
            avgSpeed: speedCount > 0 ? round(speedSum / Double(speedCount), 10) : 0,
            avgHDOP: hdopCount > 0 ? round(hdopSum / Double(hdopCount), 100) : 99,
            odometerEndM: maxOdo,
            pingCount: pts.count,
            dp2Count: dp2,
            dp3Count: dp3,
            closedByDP4: closedByDP4,
            avgSolarMV: solarCount > 0 ? Int((solarSum / Double(solarCount)).rounded()) : nil
        )
    }
}
