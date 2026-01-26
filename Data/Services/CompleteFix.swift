// CompleteFix.swift
// ADD THIS FILE to Data/Services
// One-click fix for ALL issues

import Foundation
import SwiftData

@MainActor
class CompleteFix {
    
    static func fixEverything(context: ModelContext) async {
        print("🔧 STARTING COMPLETE FIX")
        print(String(repeating: "=", count: 50))
        
        let userId = AuthService.shared.currentUserId() ?? "guest"
        print("👤 Current User: \(userId)")
        
        // STEP 1: Migrate all guest items to current user
        print("\n📝 STEP 1: Migrating userId...")
        await migrateUserId(context: context, userId: userId)
        
        // STEP 2: Create LogEntries for items that don't have them
        print("\n📝 STEP 2: Creating LogEntries...")
        await createMissingLogEntries(context: context, userId: userId)
        
        // STEP 3: Recalculate badges
        print("\n📝 STEP 3: Recalculating badges...")
        await recalculateBadges(context: context)
        
        print("\n✅ COMPLETE FIX DONE!")
        print(String(repeating: "=", count: 50))
    }
    
    private static func migrateUserId(context: ModelContext, userId: String) async {
        if userId == "guest" {
            print("⚠️ Already guest, skipping")
            return
        }
        
        var totalMigrated = 0
        
        // UserItems
        let userItemDesc = FetchDescriptor<UserItem>()
        if let items = try? context.fetch(userItemDesc) {
            let guestItems = items.filter { $0.ownerId == "guest" }
            print("  Found \(guestItems.count) guest UserItems")
            for item in guestItems {
                item.ownerId = userId
                totalMigrated += 1
            }
        }
        
        // LogEntries
        let logDesc = FetchDescriptor<LogEntry>()
        if let logs = try? context.fetch(logDesc) {
            let guestLogs = logs.filter { $0.ownerId == "guest" }
            print("  Found \(guestLogs.count) guest LogEntries")
            for log in guestLogs {
                log.ownerId = userId
                totalMigrated += 1
            }
        }
        
        // Scores
        let scoreDesc = FetchDescriptor<Score>()
        if let scores = try? context.fetch(scoreDesc) {
            let guestScores = scores.filter { $0.ownerId == "guest" }
            print("  Found \(guestScores.count) guest Scores")
            for score in guestScores {
                score.ownerId = userId
                totalMigrated += 1
            }
        }
        
        // Movies
        let movieDesc = FetchDescriptor<Movie>()
        if let movies = try? context.fetch(movieDesc) {
            let guestMovies = movies.filter { $0.ownerId == "guest" }
            print("  Found \(guestMovies.count) guest Movies")
            for movie in guestMovies {
                movie.ownerId = userId
                totalMigrated += 1
            }
        }
        
        try? context.save()
        print("  ✅ Migrated \(totalMigrated) records to \(userId)")
    }
    
    private static func createMissingLogEntries(context: ModelContext, userId: String) async {
        // Get ALL UserItems without predicate
        let itemDesc = FetchDescriptor<UserItem>()
        
        guard let allItems = try? context.fetch(itemDesc) else {
            print("  ❌ Failed to fetch UserItems")
            return
        }
        
        // Filter in memory for seen items
        let seenItems = allItems.filter { $0.state == .seen }
        
        print("  Found \(seenItems.count) seen items")
        
        // Get existing LogEntries
        let logDesc = FetchDescriptor<LogEntry>()
        let existingLogs = (try? context.fetch(logDesc)) ?? []
        let existingMovieIDs = Set(existingLogs.compactMap { $0.movie?.id })
        
        print("  Found \(existingLogs.count) existing LogEntries")
        
        // Create missing ones
        var created = 0
        for item in seenItems {
            guard let movie = item.movie else { continue }
            
            if !existingMovieIDs.contains(movie.id) {
                let log = LogEntry(
                    createdAt: item.createdAt,
                    rating: nil,
                    watchedOn: item.createdAt, // Use item creation date as watch date
                    whereWatched: nil,
                    withWho: nil,
                    notes: nil,
                    movie: movie,
                    ownerId: userId
                )
                context.insert(log)
                created += 1
            }
        }
        
        try? context.save()
        print("  ✅ Created \(created) LogEntries")
    }
    
    private static func recalculateBadges(context: ModelContext) async {
        let logDesc = FetchDescriptor<LogEntry>()
        guard let allLogs = try? context.fetch(logDesc) else {
            print("  ❌ Failed to fetch logs")
            return
        }
        
        let inputs = allLogs.compactMap { log -> BadgeInput? in
            guard let movie = log.movie else { return nil }
            return BadgeInput(watchedOn: log.watchedOn, genreIDs: movie.genreIDs)
        }
        
        print("  Processing \(inputs.count) logs for badges")
        BadgeService.shared.calculateBadges(inputs: inputs)
        print("  ✅ Badges recalculated")
    }
}
