// MigrationHelper.swift
// REPLACE your MigrationHelper.swift with this FIXED version

import Foundation
import SwiftData

@MainActor
class MigrationHelper {
    
    static func addLogEntriesForImportedItems(context: ModelContext) async {
        print("🔄 Starting migration...")
        
        // Get current user
        let userId = AuthService.shared.currentUserId() ?? "guest"
        
        // Capture the seen state before Predicate
        let seenState = UserItem.State.seen
        
        // Get all UserItems that are seen
        let userItemDescriptor = FetchDescriptor<UserItem>(
            predicate: #Predicate<UserItem> { item in
                item.state == seenState && item.ownerId == userId
            }
        )
        
        guard let seenItems = try? context.fetch(userItemDescriptor) else {
            print("❌ Failed to fetch UserItems")
            return
        }
        
        print("📊 Found \(seenItems.count) seen items")
        
        // Get all existing LogEntries
        let logDescriptor = FetchDescriptor<LogEntry>()
        let existingLogs = (try? context.fetch(logDescriptor)) ?? []
        let existingLogMovieIDs = Set(existingLogs.compactMap { $0.movie?.id })
        
        var addedCount = 0
        
        // For each seen item without a LogEntry, create one
        for item in seenItems {
            guard let movie = item.movie else { continue }
            
            // Skip if already has a log
            if existingLogMovieIDs.contains(movie.id) {
                continue
            }
            
            // Create LogEntry
            let log = LogEntry(
                createdAt: item.createdAt,
                rating: nil,
                watchedOn: nil, // No date for imported items
                whereWatched: nil,
                withWho: nil,
                notes: nil,
                movie: movie,
                ownerId: userId
            )
            
            context.insert(log)
            addedCount += 1
        }
        
        // Save
        do {
            try context.save()
            print("✅ Migration complete! Added \(addedCount) LogEntry records")
        } catch {
            print("❌ Failed to save: \(error)")
        }
        
        // Recalculate badges
        print("🏅 Recalculating badges...")
        let allLogs = (try? context.fetch(FetchDescriptor<LogEntry>())) ?? []
        let inputs = allLogs.compactMap { log -> BadgeInput? in
            guard let movie = log.movie else { return nil }
            return BadgeInput(watchedOn: log.watchedOn, genreIDs: movie.genreIDs)
        }
        
        BadgeService.shared.calculateBadges(inputs: inputs)
        print("✅ Badges updated! Processed \(inputs.count) logs")
    }
}
