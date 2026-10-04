import Foundation

/// RFC-4180 CSV parser. Works on UTF-8 bytes and slices fields out in one pass,
/// which keeps large IOT High Site exports fast.
enum CSVParser {
    private static let quote = UInt8(ascii: "\"")
    private static let comma = UInt8(ascii: ",")
    private static let cr = UInt8(ascii: "\r")
    private static let lf = UInt8(ascii: "\n")

    static func rows(_ text: String) -> [[String]] {
        let bytes = Array(text.utf8)
        let n = bytes.count
        var rows: [[String]] = []
        var i = 0

        func string(_ start: Int, _ end: Int) -> String {
            String(decoding: bytes[start..<end], as: UTF8.self)
        }

        while i < n {
            var row: [String] = []
            while i < n {
                if bytes[i] == quote {
                    i += 1
                    var value = ""
                    var segStart = i
                    while i < n {
                        if bytes[i] == quote {
                            if i + 1 < n && bytes[i + 1] == quote {
                                value += string(segStart, i) + "\""
                                i += 2
                                segStart = i
                            } else {
                                break
                            }
                        } else {
                            i += 1
                        }
                    }
                    value += string(segStart, min(i, n))
                    row.append(value)
                    i += 1 // closing quote
                    // Tolerate stray characters between a closing quote and the delimiter.
                    while i < n && bytes[i] != comma && bytes[i] != cr && bytes[i] != lf { i += 1 }
                } else {
                    let start = i
                    while i < n && bytes[i] != comma && bytes[i] != cr && bytes[i] != lf { i += 1 }
                    row.append(string(start, i).trimmingCharacters(in: .whitespaces))
                }
                if i < n && bytes[i] == comma {
                    i += 1
                    if i == n { row.append("") }
                    continue
                }
                break
            }
            while i < n && (bytes[i] == cr || bytes[i] == lf) { i += 1 }
            if !row.isEmpty && !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
        }
        return rows
    }
}
