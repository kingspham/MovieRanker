// RecalculateAllScores.swift
// ADD THIS FILE to Data/Services
// Recalculates ALL existing scores using the new improved algorithm

import Foundation
import SwiftData

@MainActor
class RecalculateAllScores {
    
    static func recalculateAllUserScores(context: ModelContext) async {
        print("\n🔄 RECALCULATING ALL SCORES WITH NEW ALGORITHM")
        print(String(repeating: "=", count: 50))
        
        let userId = AuthService.shared.currentUserId() ?? "guest"
        print("👤 User: \(userId)")
        
        // Get all user's scores
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
        
        // Sort by current score (highest to lowest)
        // This preserves relative ranking order
        let sortedScores = userScores.sorted { $0.display100 > $1.display100 }
        
        print("📊 Score range before: \(sortedScores.last?.display100 ?? 0) - \(sortedScores.first?.display100 ?? 0)")
        
        // Apply NEW algorithm
        let count = Double(sortedScores.count)
        
        for (index, scoreObj) in sortedScores.enumerated() {
            if count == 1 {
                scoreObj.display100 = 100
            } else {
                // Calculate percentile (0.0 = best, 1.0 = worst)
                let percentile = Double(index) / (count - 1)
                
                // Apply curve for better psychological distribution
                let curved = pow(percentile, 1.2)
                
                // Map to 100-1 range
                let newScore = 100.0 - (curved * 99.0)
                
                scoreObj.display100 = max(1, Int(newScore))
            }
        }
        
        print("📊 Score range after: \(sortedScores.last?.display100 ?? 0) - \(sortedScores.first?.display100 ?? 0)")
        
        // Save
        do {
            try context.save()
            print("✅ Recalculated \(sortedScores.count) scores")
            
            // Show some examples
            print("\n📋 Sample scores (best to worst):")
            for i in [0, sortedScores.count/4, sortedScores.count/2, (sortedScores.count*3)/4, sortedScores.count-1] {
                if i < sortedScores.count {
                    let score = sortedScores[i]
                    print("  Position \(i): Score \(score.display100)")
                }
            }
            
        } catch {
            print("❌ Failed to save: \(error)")
        }
        
        print(String(repeating: "=", count: 50))
        print("✅ RECALCULATION COMPLETE!\n")
    }
}
