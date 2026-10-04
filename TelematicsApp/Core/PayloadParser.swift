import Foundation

/// Decodes an IOT High Site payload export (CSV with a "Payload" column) into pings.
///
/// Payload fields used: [4] IMEI, [10] UTC timestamp "YY-MM-DD HH:MM:SS", [11]/[12] lat/lon,
/// [13] firmware, [15] data point, [16] movement, [17] speed km/h, [18] heading,
/// [19] elevation, [20] HDOP, [21] odometer m, [22] usage min, [23] solar mV (v371 only).
enum PayloadParser {
    struct Result {
        var pings: [Ping] = []
        var skipped = 0
        var skippedStatusMessages = 0
    }

    enum ParseError: LocalizedError {
        case noDataRows
        case noPayloadColumn(header: [String])

        var errorDescription: String? {
            switch self {
            case .noDataRows: "No data rows found"
            case .noPayloadColumn(let header): "No \"Payload\" column. Header: " + header.joined(separator: ", ")
            }
        }
    }

    static func parse(_ text: String, board: BoardVersion) throws -> Result {
        let rows = CSVParser.rows(text)
        guard rows.count >= 2 else { throw ParseError.noDataRows }
        let header = rows[0].map { $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{FEFF}"))).lowercased() }
        guard let pIdx = header.firstIndex(of: "payload") else { throw ParseError.noPayloadColumn(header: rows[0]) }

        var result = Result()
        for r in 1..<rows.count {
            let row = rows[r]
            guard pIdx < row.count, !row[pIdx].isEmpty else { result.skipped += 1; continue }
            let parts = row[pIdx].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 23 else { result.skipped += 1; continue }

            // Device status / firmware-report messages share header fields 0-14 with real
            // pings but carry a version string like "1.0.0" in field 15. Reject them, and any
            // row with more fields than a real GPS ping (24-26 including a trailing comma).
            let dpField = parts[15].trimmingCharacters(in: .whitespaces)
            guard !dpField.isEmpty, dpField.allSatisfy(\.isASCIIDigit), parts.count <= 26 else {
                result.skipped += 1
                result.skippedStatusMessages += 1
                continue
            }
            guard let date = parseUTC(parts[10]) else { result.skipped += 1; continue }
            guard let lat = Double(parts[11].trimmingCharacters(in: .whitespaces)),
                  let lon = Double(parts[12].trimmingCharacters(in: .whitespaces)),
                  abs(lat) <= 90, abs(lon) <= 180 else { result.skipped += 1; continue }
            guard let dp = Int(dpField) else { result.skipped += 1; continue }

            let solar: Double? = (board == .v371 && parts.count > 23) ? nonZero(num(parts[23])) : nil

            result.pings.append(Ping(
                id: r,
                deviceID: parts[4].trimmingCharacters(in: .whitespaces),
                firmware: parts[13].trimmingCharacters(in: .whitespaces),
                date: date,
                latitude: lat,
                longitude: lon,
                dataPoint: dp,
                movement: Int(num(parts[16])),
                speed: num(parts[17]),
                direction: num(parts[18]),
                elevation: num(parts[19]),
                hdop: nonZero(num(parts[20])) ?? 99,
                odometerM: Int(num(parts[21])),
                usageMin: Int(num(parts[22])),
                solarMV: solar,
                board: board
            ))
        }
        result.pings.sort { $0.date < $1.date }
        return result
    }

    /// "YY-MM-DD HH:MM:SS" in UTC.
    static func parseUTC(_ s: String) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        let comps = trimmed.split(whereSeparator: { $0 == "-" || $0 == " " || $0 == ":" }).compactMap { Int($0) }
        guard comps.count == 6, trimmed.count == 17 else { return nil }
        var dc = DateComponents()
        dc.year = 2000 + comps[0]; dc.month = comps[1]; dc.day = comps[2]
        dc.hour = comps[3]; dc.minute = comps[4]; dc.second = comps[5]
        return utcCalendar.date(from: dc)
    }

    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Lenient number parse: blank or garbage reads as 0, like the website.
    private static func num(_ s: String) -> Double {
        Double(s.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private static func nonZero(_ v: Double) -> Double? { v == 0 ? nil : v }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
