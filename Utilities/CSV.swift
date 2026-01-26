import Foundation

/// Lightweight CSV utilities used by ImportDetector and import flows.
/// Supports commas by default, quoted fields, escaped quotes (`""`), and CRLF/LF newlines.
enum CSV {

    struct Row: Sendable, Hashable {
        var fields: [String]
    }

    struct Table: Sendable, Hashable {
        var header: [String]
        var rows: [Row]
    }

    /// Parse a CSV string into a Table.
    static func parse(_ string: String, delimiter: Character = ",") -> Table {
        let lines = normalizeNewlines(in: string).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first else {
            return Table(header: [], rows: [])
        }

        let header = parseLine(first, delimiter: delimiter)
        let body = lines.dropFirst().map { Row(fields: parseLine($0, delimiter: delimiter)) }
        return Table(header: header, rows: body)
    }

    /// Case-insensitive index of a column name inside a header.
    /// Returns the first exact match; if not found, returns `nil`.
    static func index(of name: String, in header: [String]) -> Int? {
        let needle = name.lowercased()
        return header.firstIndex { $0.lowercased() == needle }
    }

    // MARK: - Internals

    private static func normalizeNewlines(in s: String) -> String {
        // Convert CRLF and CR into LF to simplify splitting.
        s.replacingOccurrences(of: "\r\n", with: "\n")
         .replacingOccurrences(of: "\r", with: "\n")
    }

    /// RFC4180-ish line parser with support for quotes and escaped quotes.
    private static func parseLine(_ line: String, delimiter: Character) -> [String] {
        var result: [String] = []
        var field = ""
        var inQuotes = false
        var i = line.startIndex

        while i < line.endIndex {
            let ch = line[i]
            if inQuotes {
                if ch == "\"" {
                    // Lookahead for escaped quote
                    let next = line.index(after: i)
                    if next < line.endIndex, line[next] == "\"" {
                        field.append("\"")
                        i = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else {
                if ch == "\"" {
                    inQuotes = true
                } else if ch == delimiter {
                    result.append(field)
                    field = ""
                } else {
                    field.append(ch)
                }
            }
            i = line.index(after: i)
        }
        result.append(field)
        return result
    }
}
