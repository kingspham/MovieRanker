// CSVManager.swift
// REPLACE your CSVManager.swift with this version
// Better date parsing for Netflix CSVs

import Foundation
import SwiftData
import UniformTypeIdentifiers

struct CSVManager {
    
    // MARK: - Export
    static func generateCSV(logs: [LogEntry], movies: [Movie], scores: [Score]) -> String {
        var csv = "Title,Year,Type,Score,Date Watched,Notes\n"
        
        for log in logs {
            let title = log.movie?.title.replacingOccurrences(of: ",", with: " ") ?? "Unknown"
            let year = log.movie?.year.map(String.init) ?? ""
            let type = log.movie?.mediaType ?? "movie"
            
            // Find score
            var scoreStr = ""
            if let mID = log.movie?.id, let s = scores.first(where: { $0.movieID == mID }) {
                scoreStr = String(s.display100)
            }
            
            let dateStr = log.watchedOn?.formatted(date: .numeric, time: .omitted) ?? ""
            let notes = log.notes?.replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: "\n", with: " ") ?? ""
            
            let row = "\(title),\(year),\(type),\(scoreStr),\(dateStr),\(notes)\n"
            csv.append(row)
        }
        return csv
    }
    
    // MARK: - Import
    struct ImportedRow: Hashable {
        let title: String
        let year: Int?
        let rating: Int?
        let date: Date?
    }
    
    static func parseCSV(url: URL) throws -> [ImportedRow] {
        let content = try String(contentsOf: url, encoding: .utf8)
        var rows: [ImportedRow] = []
        
        let lines = content.components(separatedBy: .newlines)
        guard let headerLine = lines.first else { return [] }
        
        print("📄 CSV Headers: \(headerLine)")
        
        // DYNAMIC COLUMN MAPPING
        let headers = headerLine.lowercased().components(separatedBy: ",")
        
        // Find indices
        let titleIndex = headers.firstIndex { $0.contains("name") || $0.contains("title") }
        let yearIndex = headers.firstIndex { $0.contains("year") }
        let ratingIndex = headers.firstIndex { $0.contains("rating") || $0.contains("score") }
        
        // Netflix uses "Date" or "Last Played" or similar
        // Letterboxd uses "Watched Date"
        let dateIndex = headers.firstIndex {
            $0.contains("watched date") ||
            $0.contains("date watched") ||
            $0.contains("last played") ||
            $0.contains("viewing date") ||
            ($0.contains("date") && !$0.contains("release"))
        }
        
        print("📊 Column indices - Title: \(titleIndex ?? -1), Year: \(yearIndex ?? -1), Date: \(dateIndex ?? -1)")
        
        // Date Formatters
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        
        let slashFormatter = DateFormatter()
        slashFormatter.dateFormat = "MM/dd/yy"
        
        let slashFormatter4 = DateFormatter()
        slashFormatter4.dateFormat = "MM/dd/yyyy"
        
        let dashFormatter = DateFormatter()
        dashFormatter.dateFormat = "dd/MM/yyyy"
        
        // Parse Rows
        var parsedCount = 0
        var datesFound = 0
        
        for line in lines.dropFirst() {
            let columns = line.components(separatedBy: ",")
            
            guard let tIdx = titleIndex, columns.count > tIdx else { continue }
            
            // 1. TITLE (Required)
            let titleRaw = columns[tIdx].replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
            if titleRaw.isEmpty { continue }
            
            // Netflix cleanup: "Stranger Things: Season 1" -> "Stranger Things"
            let titleClean = titleRaw.components(separatedBy: ":")[0]
            
            // 2. YEAR
            var year: Int? = nil
            if let yIdx = yearIndex, columns.count > yIdx {
                let yRaw = columns[yIdx].replacingOccurrences(of: "\"", with: "")
                year = Int(yRaw)
            }
            
            // 3. RATING
            var rating: Int? = nil
            if let rIdx = ratingIndex, columns.count > rIdx {
                let rRaw = columns[rIdx].replacingOccurrences(of: "\"", with: "")
                if let rDouble = Double(rRaw) {
                    // Letterboxd is 0-5, we want 0-100
                    rating = rDouble <= 5 ? Int(rDouble * 20) : Int(rDouble)
                }
            }
            
            // 4. DATE (Enhanced parsing)
            var date: Date? = nil
            if let dIdx = dateIndex, columns.count > dIdx {
                let dRaw = columns[dIdx].replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
                
                if !dRaw.isEmpty {
                    // Try multiple formats
                    date = isoFormatter.date(from: dRaw) ??
                           slashFormatter.date(from: dRaw) ??
                           slashFormatter4.date(from: dRaw) ??
                           dashFormatter.date(from: dRaw)
                    
                    if date != nil {
                        datesFound += 1
                    }
                }
            }
            
            rows.append(ImportedRow(title: titleClean, year: year, rating: rating, date: date))
            parsedCount += 1
        }
        
        print("✅ Parsed \(parsedCount) rows, found \(datesFound) dates")
        
        return rows
    }
}
