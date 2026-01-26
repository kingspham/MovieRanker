// RankingDiagnostic.swift
// ADD THIS to Data/Services
// Shows why "Rank All" says "all caught up"

import Foundation
import SwiftData

@MainActor
class RankingDiagnostic {
    
    static func diagnoseRanking(context: ModelContext) async {
        print("\n🔍 RANKING DIAGNOSTIC")
        print(String(repeating: "=", count: 50))
        
        let userId = AuthService.shared.currentUserId() ?? "guest"
        print("👤 User: \(userId)")
        
        // Get UserItems
        let itemDesc = FetchDescriptor<UserItem>()
        guard let allItems = try? context.fetch(itemDesc) else {
            print("❌ Can't fetch UserItems")
            return
        }
        
        let seenItems = allItems.filter { $0.state == .seen }
        let mySeenItems = seenItems.filter { $0.ownerId == userId || $0.ownerId == "guest" }
        
        print("\n📊 SEEN ITEMS:")
        print("  Total seen in DB: \(seenItems.count)")
        print("  Owned by me: \(mySeenItems.count)")
        print("  Owned by guest: \(seenItems.filter { $0.ownerId == "guest" }.count)")
        print("  Owned by \(userId.prefix(8))...: \(seenItems.filter { $0.ownerId == userId }.count)")
        
        // Get Scores
        let scoreDesc = FetchDescriptor<Score>()
        guard let allScores = try? context.fetch(scoreDesc) else {
            print("❌ Can't fetch Scores")
            return
        }
        
        let myScores = allScores.filter { $0.ownerId == userId || $0.ownerId == "guest" }
        
        print("\n📊 SCORES:")
        print("  Total scores in DB: \(allScores.count)")
        print("  My scores: \(myScores.count)")
        print("  Owned by guest: \(allScores.filter { $0.ownerId == "guest" }.count)")
        print("  Owned by \(userId.prefix(8))...: \(allScores.filter { $0.ownerId == userId }.count)")
        
        // Find unranked
        let rankedMovieIDs = Set(myScores.map { $0.movieID })
        var unrankedCount = 0
        
        for item in mySeenItems {
            if let movie = item.movie, !rankedMovieIDs.contains(movie.id) {
                unrankedCount += 1
            }
        }
        
        print("\n🎯 RANKING STATUS:")
        print("  Seen items: \(mySeenItems.count)")
        print("  Ranked items: \(myScores.count)")
        print("  Unranked items: \(unrankedCount)")
        
        if unrankedCount == 0 && mySeenItems.count > 0 {
            print("\n⚠️ PROBLEM FOUND!")
            print("  You have \(mySeenItems.count) seen items but \(myScores.count) scores.")
            print("  They should be different unless you ranked everything!")
            
            // Check if Score movieIDs match UserItem movieIDs
            let seenMovieIDs = Set(mySeenItems.compactMap { $0.movie?.id })
            let mismatch = myScores.count - seenMovieIDs.count
            
            if mismatch > 0 {
                print("  ❌ You have \(mismatch) scores for movies you haven't seen!")
                print("  This means Score.ownerId doesn't match UserItem ownership")
            }
        }
        
        // Sample the first 5 items
        print("\n📋 SAMPLE (first 5 seen items):")
        for item in mySeenItems.prefix(5) {
            let movieTitle = item.movie?.title ?? "nil"
            let movieId = item.movie?.id.uuidString.prefix(8) ?? "nil"
            let hasScore = item.movie.map { rankedMovieIDs.contains($0.id) } ?? false
            print("  - \(movieTitle) (ID: \(movieId)..., Ranked: \(hasScore))")
        }
        
        print(String(repeating: "=", count: 50))
    }
}
