// FixWatchDatesFromCSV.swift
// IMPROVED VERSION - Better title matching

import Foundation
import SwiftData

@MainActor
class FixWatchDatesFromCSV {
    
    static func fixDatesFromNetflixCSV(csvData: Data, context: ModelContext) async {
        print("\n📅 FIXING WATCH DATES FROM NETFLIX CSV (IMPROVED MATCHING)")
        print(String(repeating: "=", count: 60))
        
        let userId = AuthService.shared.currentUserId() ?? "guest"
        
        // Parse CSV
        guard let csvString = String(data: csvData, encoding: .utf8) else {
            print("❌ Failed to read CSV data")
            return
        }
        
        let lines = csvString.components(separatedBy: .newlines)
        guard lines.count > 1 else {
            print("❌ CSV is empty")
            return
        }
        
        print("📄 CSV has \(lines.count - 1) entries")
        
        // Date formatters
        let formatters = [
            "M/d/yy", "M/dd/yy", "MM/d/yy", "MM/dd/yy",
            "M/d/yyyy", "M/dd/yyyy", "MM/d/yyyy", "MM/dd/yyyy"
        ].map { format -> DateFormatter in
            let f = DateFormatter()
            f.dateFormat = format
            return f
        }
        
        // Parse CSV into array of (title, date) tuples
        var csvEntries: [(title: String, date: Date)] = []
        
        for line in lines.dropFirst() {
            let columns = line.components(separatedBy: ",")
            guard columns.count >= 2 else { continue }
            
            let titleRaw = columns[0].replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
            let dateRaw = columns[1].replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
            
            if titleRaw.isEmpty || dateRaw.isEmpty { continue }
            
            // Parse date with all formatters
            var parsedDate: Date? = nil
            for formatter in formatters {
                if let date = formatter.date(from: dateRaw) {
                    parsedDate = date
                    break
                }
            }
            
            guard let date = parsedDate else { continue }
            csvEntries.append((title: titleRaw, date: date))
        }
        
        print("📊 Parsed \(csvEntries.count) titles with dates")
        
        // Get all LogEntries
        let logDesc = FetchDescriptor<LogEntry>()
        guard let allLogs = try? context.fetch(logDesc) else {
            print("❌ Failed to fetch LogEntries")
            return
        }
        
        let userLogs = allLogs.filter { $0.ownerId == userId || $0.ownerId == "guest" }
        print("📊 Found \(userLogs.count) LogEntries to update")
        
        // Match and update with improved logic
        var updated = 0
        var exactMatches = 0
        var fuzzyMatches = 0
        
        for log in userLogs {
            guard let movieTitle = log.movie?.title else { continue }
            
            // Clean the database title
            let cleanMovieTitle = movieTitle
                .replacingOccurrences(of: ":", with: "")
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
                .trimmingCharacters(in: .whitespaces)
            
            // Try to find matching CSV entry
            var matchedDate: Date? = nil
            
            // Strategy 1: Exact match
            for entry in csvEntries {
                let cleanCSVTitle = entry.title
                    .replacingOccurrences(of: ":", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .lowercased()
                    .trimmingCharacters(in: .whitespaces)
                
                if cleanMovieTitle == cleanCSVTitle {
                    matchedDate = entry.date
                    exactMatches += 1
                    break
                }
            }
            
            // Strategy 2: CSV title starts with movie title
            if matchedDate == nil {
                for entry in csvEntries {
                    let cleanCSVTitle = entry.title
                        .replacingOccurrences(of: ":", with: "")
                        .replacingOccurrences(of: "-", with: "")
                        .lowercased()
                        .trimmingCharacters(in: .whitespaces)
                    
                    if cleanCSVTitle.hasPrefix(cleanMovieTitle) && cleanMovieTitle.count > 5 {
                        matchedDate = entry.date
                        fuzzyMatches += 1
                        break
                    }
                }
            }
            
            // Strategy 3: Movie title starts with CSV title
            if matchedDate == nil {
                for entry in csvEntries {
                    let cleanCSVTitle = entry.title
                        .replacingOccurrences(of: ":", with: "")
                        .replacingOccurrences(of: "-", with: "")
                        .lowercased()
                        .trimmingCharacters(in: .whitespaces)
                    
                    if cleanMovieTitle.hasPrefix(cleanCSVTitle) && cleanCSVTitle.count > 5 {
                        matchedDate = entry.date
                        fuzzyMatches += 1
                        break
                    }
                }
            }
            
            // Update if we found a match
            if let date = matchedDate {
                log.watchedOn = date
                updated += 1
                
                // Debug first 5 matches
                if updated <= 5 {
                    print("✅ Matched: '\(movieTitle)' → \(date.formatted(date: .abbreviated, time: .omitted))")
                }
            } else {
                // Debug first 5 non-matches
                if (userLogs.count - updated) <= 5 {
                    print("❌ No match: '\(movieTitle)'")
                }
            }
        }
        
        // Save
        do {
            try context.save()
            print("\n✅ Updated \(updated) LogEntries with watch dates")
            print("   📊 Exact matches: \(exactMatches)")
            print("   📊 Fuzzy matches: \(fuzzyMatches)")
            print("   📊 Match rate: \(updated)/\(userLogs.count) (\(Int(Double(updated)/Double(userLogs.count)*100))%)")
        } catch {
            print("❌ Failed to save: \(error)")
        }
        
        print(String(repeating: "=", count: 60))
        print("✅ DATE FIX COMPLETE!\n")
    }
}
