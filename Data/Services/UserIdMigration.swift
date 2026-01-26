// UserIdMigration.swift
// ADD THIS FILE to Data/Services
// Fixes userId mismatch - changes all "guest" items to your actual userId

import Foundation
import SwiftData

@MainActor
class UserIdMigration {
    
    static func migrateGuestItemsToCurrentUser(context: ModelContext) async {
        print("🔄 Starting userId migration...")
        
        // Get current user
        let userId = AuthService.shared.currentUserId() ?? "guest"
        
        if userId == "guest" {
            print("⚠️ Already logged in as guest, no migration needed")
            return
        }
        
        print("👤 Current user: \(userId)")
        
        var updatedCount = 0
        
        // 1. Migrate UserItems
        let userItemDesc = FetchDescriptor<UserItem>()
        if let allUserItems = try? context.fetch(userItemDesc) {
            let guestItems = allUserItems.filter { $0.ownerId == "guest" }
            print("📊 Found \(guestItems.count) UserItems with 'guest' ownerId")
            
            for item in guestItems {
                item.ownerId = userId
                updatedCount += 1
            }
        }
        
        // 2. Migrate LogEntries
        let logDesc = FetchDescriptor<LogEntry>()
        if let allLogs = try? context.fetch(logDesc) {
            let guestLogs = allLogs.filter { $0.ownerId == "guest" }
            print("📊 Found \(guestLogs.count) LogEntries with 'guest' ownerId")
            
            for log in guestLogs {
                log.ownerId = userId
                updatedCount += 1
            }
        }
        
        // 3. Migrate Scores
        let scoreDesc = FetchDescriptor<Score>()
        if let allScores = try? context.fetch(scoreDesc) {
            let guestScores = allScores.filter { $0.ownerId == "guest" }
            print("📊 Found \(guestScores.count) Scores with 'guest' ownerId")
            
            for score in guestScores {
                score.ownerId = userId
                updatedCount += 1
            }
        }
        
        // 4. Migrate Movies
        let movieDesc = FetchDescriptor<Movie>()
        if let allMovies = try? context.fetch(movieDesc) {
            let guestMovies = allMovies.filter { $0.ownerId == "guest" }
            print("📊 Found \(guestMovies.count) Movies with 'guest' ownerId")
            
            for movie in guestMovies {
                movie.ownerId = userId
                updatedCount += 1
            }
        }
        
        // Save
        do {
            try context.save()
            print("✅ Migration complete! Updated \(updatedCount) records to user \(userId)")
        } catch {
            print("❌ Failed to save: \(error)")
        }
    }
}
