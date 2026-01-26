// CleanSlateHelper.swift
// ADD THIS FILE to Data/Services
// Use this to completely delete all data and start fresh

import Foundation
import SwiftData

@MainActor
class CleanSlateHelper {
    
    static func deleteAllImportedData(context: ModelContext) async {
        print("🗑️ Starting clean slate deletion...")
        
        var totalDeleted = 0
        
        // 1. Delete all UserItems
        let userItemDesc = FetchDescriptor<UserItem>()
        if let items = try? context.fetch(userItemDesc) {
            print("📊 Deleting \(items.count) UserItems")
            for item in items {
                context.delete(item)
                totalDeleted += 1
            }
        }
        
        // 2. Delete all LogEntries
        let logDesc = FetchDescriptor<LogEntry>()
        if let logs = try? context.fetch(logDesc) {
            print("📊 Deleting \(logs.count) LogEntries")
            for log in logs {
                context.delete(log)
                totalDeleted += 1
            }
        }
        
        // 3. Delete all Scores
        let scoreDesc = FetchDescriptor<Score>()
        if let scores = try? context.fetch(scoreDesc) {
            print("📊 Deleting \(scores.count) Scores")
            for score in scores {
                context.delete(score)
                totalDeleted += 1
            }
        }
        
        // 4. Delete all Movies
        let movieDesc = FetchDescriptor<Movie>()
        if let movies = try? context.fetch(movieDesc) {
            print("📊 Deleting \(movies.count) Movies")
            for movie in movies {
                context.delete(movie)
                totalDeleted += 1
            }
        }
        
        // Save
        do {
            try context.save()
            print("✅ Clean slate complete! Deleted \(totalDeleted) records")
            print("🎯 You can now re-import your CSV fresh")
        } catch {
            print("❌ Failed to save: \(error)")
        }
    }
}
