// RecalculateAllScores.swift
// IMPROVED: Better score distribution that allows natural clustering

import Foundation
import SwiftData

@MainActor
class RecalculateAllScores {

    /// Recalculates all scores using an improved algorithm that:
    /// 1. Allows natural gaps between scores (not just even distribution)
    /// 2. Creates clusters based on existing score patterns
    /// 3. Preserves relative order while spreading scores more naturally
    static func recalculateAllUserScores(context: ModelContext) async {
        print("\n🔄 RECALCULATING SCORES WITH NATURAL DISTRIBUTION")
        print(String(repeating: "=", count: 50))

        let userId = AuthService.shared.currentUserId() ?? "guest"
        print("👤 User: \(userId)")

        let scoreDesc = FetchDescriptor<Score>()
        guard let allScores = try? context.fetch(scoreDesc) else {
            print("❌ Failed to fetch scores")
            return
        }

        let userScores = allScores.filter { $0.ownerId == userId || $0.ownerId == "guest" }

        print("📊 Found \(userScores.count) scores to recalculate")

        if userScores.isEmpty {
            print("⚠️ No scores found")
            return
        }

        // Sort by current score (highest to lowest) to preserve relative order
        let sortedScores = userScores.sorted { $0.display100 > $1.display100 }

        print("📊 Score range before: \(sortedScores.last?.display100 ?? 0) - \(sortedScores.first?.display100 ?? 0)")

        let count = sortedScores.count

        if count == 1 {
            sortedScores[0].display100 = 85
        } else {
            // NEW ALGORITHM: Natural distribution with tiers
            // Divide into sentiment tiers and distribute within each tier

            // Define tier boundaries (approximate percentages)
            let lovedCount = max(1, Int(Double(count) * 0.20))  // Top 20% = "Loved"
            let likedCount = max(1, Int(Double(count) * 0.40))  // Next 40% = "Liked"
            // Remaining ~40% = "Meh/Disliked"

            for (index, scoreObj) in sortedScores.enumerated() {
                let newScore: Int

                if index < lovedCount {
                    // LOVED tier: 85-99
                    // Use exponential curve to spread out the top
                    let tierPosition = Double(index) / Double(max(1, lovedCount - 1))
                    let curved = pow(tierPosition, 0.7) // Slower curve at top
                    newScore = Int(99.0 - (curved * 14.0)) // 99 down to 85
                } else if index < lovedCount + likedCount {
                    // LIKED tier: 55-84
                    let tierIndex = index - lovedCount
                    let tierPosition = Double(tierIndex) / Double(max(1, likedCount - 1))
                    let curved = pow(tierPosition, 1.0) // Linear within tier
                    newScore = Int(84.0 - (curved * 29.0)) // 84 down to 55
                } else {
                    // MEH/DISLIKED tier: 1-54
                    let tierIndex = index - lovedCount - likedCount
                    let remaining = count - lovedCount - likedCount
                    let tierPosition = Double(tierIndex) / Double(max(1, remaining - 1))
                    // Steeper curve at bottom to allow very low scores
                    let curved = pow(tierPosition, 1.5)
                    newScore = Int(54.0 - (curved * 53.0)) // 54 down to 1
                }

                scoreObj.display100 = max(1, min(99, newScore))
            }
        }

        print("📊 Score range after: \(sortedScores.last?.display100 ?? 0) - \(sortedScores.first?.display100 ?? 0)")

        do {
            try context.save()
            print("✅ Recalculated \(sortedScores.count) scores with natural distribution")

            // Show distribution
            print("\n📋 Score distribution:")
            let loved = sortedScores.filter { $0.display100 >= 85 }.count
            let liked = sortedScores.filter { $0.display100 >= 55 && $0.display100 < 85 }.count
            let meh = sortedScores.filter { $0.display100 < 55 }.count
            print("  Loved (85-99): \(loved) items")
            print("  Liked (55-84): \(liked) items")
            print("  Meh (1-54): \(meh) items")

            print("\n📋 Sample scores:")
            for i in [0, count/4, count/2, (count*3)/4, count-1] {
                if i < count {
                    print("  Position \(i): Score \(sortedScores[i].display100)")
                }
            }

        } catch {
            print("❌ Failed to save: \(error)")
        }

        print(String(repeating: "=", count: 50))
        print("✅ RECALCULATION COMPLETE!\n")
    }
}
