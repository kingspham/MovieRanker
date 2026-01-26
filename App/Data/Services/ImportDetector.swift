import Foundation

// MARK: - Types

struct ImportSummary {
    let detected: ImportFormat
    let total: Int
}

enum ImportFormat {
    case letterboxd
    case trakt
    case generic
}

struct ImportRow {
    let title: String
    let year: Int?
    let watchedOn: Date?
    let notes: String?
    let labels: [String]?
}

// MARK: - Detector

enum ImportDetector {
    static func detect(table: CSV.Table) -> ImportSummary? {
        let h = table.header.map { $0.lowercased() }

        func has(_ s: String) -> Bool { h.contains(s.lowercased()) }

        // Letterboxd diary export
        if has("title") && has("diary entry") {
            return ImportSummary(detected: .letterboxd, total: table.rows.count)
        }

        // Trakt CSV
        if has("movie.title") && has("watched_at") {
            return ImportSummary(detected: .trakt, total: table.rows.count)
        }

        // Generic: needs at least a title column (or a column that contains "title")
        if has("title") || h.contains(where: { $0.contains("title") }) {
            return ImportSummary(detected: .generic, total: table.rows.count)
        }
        return nil
    }

    static func mapRows(table: CSV.Table, format: ImportFormat) -> [ImportRow] {
        switch format {
        case .letterboxd:
            let idxTitle = CSV.index(of: "Title", in: table.header)
            let idxYear  = CSV.index(of: "Year", in: table.header)
            let idxDate  = CSV.index(of: "Date", in: table.header)
            let idxNote  = CSV.index(of: "Diary Entry", in: table.header)
            let idxTags  = CSV.index(of: "Tags", in: table.header)

            return table.rows.map { r in
                ImportRow(
                    title: value(r, idxTitle) ?? "",
                    year: value(r, idxYear).flatMap(Int.init),
                    watchedOn: value(r, idxDate).flatMap(Date.fromYYYYMMdd) ?? value(r, idxDate).flatMap(Date.fromISO8601),
                    notes: value(r, idxNote),
                    labels: value(r, idxTags).map { raw in
                        raw.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
                    }
                )
            }

        case .trakt:
            let tIdx = CSV.index(of: "movie.title", in: table.header)
            let yIdx = CSV.index(of: "movie.year", in: table.header)
            let dIdx = CSV.index(of: "watched_at", in: table.header)

            return table.rows.map { r in
                ImportRow(
                    title: value(r, tIdx) ?? "",
                    year: value(r, yIdx).flatMap(Int.init),
                    watchedOn: value(r, dIdx).flatMap(Date.fromISO8601),
                    notes: nil,
                    labels: nil
                )
            }

        case .generic:
            // Try a bunch of common names
            let titleIdx = CSV.index(of: "title", in: table.header) ?? firstMatch(["movie","name","film"], in: table.header)
            let yearIdx  = CSV.index(of: "year", in: table.header)
            let dateIdx  = firstMatch(["date","watched","watched_on","viewed_at"], in: table.header)
            let notesIdx = firstMatch(["notes","review","comment"], in: table.header)
            let tagsIdx  = firstMatch(["tags","labels"], in: table.header)

            return table.rows.map { r in
                ImportRow(
                    title: value(r, titleIdx) ?? "",
                    year: value(r, yearIdx).flatMap(Int.init),
                    watchedOn: value(r, dateIdx).flatMap(Date.fromYYYYMMdd) ?? value(r, dateIdx).flatMap(Date.fromISO8601),
                    notes: value(r, notesIdx),
                    labels: value(r, tagsIdx).map { raw in
                        raw.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
                    }
                )
            }
        }
    }

    // MARK: - Helpers

    private static func value(_ row: CSV.Row, _ idx: Int?) -> String? {
        guard let i = idx, i >= 0, i < row.fields.count else { return nil }
        let v = row.fields[i].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    private static func firstMatch(_ candidates: [String], in header: [String]) -> Int? {
        let lc = header.map { $0.lowercased() }
        for c in candidates {
            if let i = lc.firstIndex(where: { $0 == c || $0.contains(c) }) { return i }
        }
        return nil
    }
}

// MARK: - Date parsing helpers

extension Date {
    nonisolated static func fromYYYYMMdd(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    nonisolated static func fromISO8601(_ s: String) -> Date? {
        ISO8601DateFormatter().date(from: s)
    }
}
