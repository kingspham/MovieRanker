//
//  PairwiseScheduler.swift
//  MovieRanker
//
//  Suggests the next pair to compare, balancing exploration (uncertain pairs)
//  and avoiding recent repeats.
//

import Foundation

public struct PairHistory: Hashable, Codable, Sendable {
    public let aId: String
    public let bId: String
    public let comparisons: Int
    public init(aId: String, bId: String, comparisons: Int) {
        self.aId = aId
        self.bId = bId
        self.comparisons = comparisons
    }
}

public struct PairwiseScheduler {

    /// Suggest next pair of ids to present.
    /// - Parameters:
    ///   - itemIds: all candidate ids
    ///   - currentScores: map id → BTL strength
    ///   - history: recent pairs with counts (to avoid spamming same pairs)
    ///   - recentBlocklist: ids to avoid for now (just shown, etc.)
    ///   - maxTries: attempts before giving up
    /// - Returns: (leftId, rightId) or nil
    public static func nextPair(
        itemIds: [String],
        currentScores: [String: Double],
        history: [PairHistory],
        recentBlocklist: Set<String> = [],
        maxTries: Int = 200
    ) -> (String, String)? {

        guard itemIds.count >= 2 else { return nil }

        // Build helper structures
        let score = { (id: String) -> Double in currentScores[id] ?? 1.0 }
        var pairCount: [PairKey:Int] = [:]
        for h in history {
            let key = PairKey(h.aId, h.bId)
            pairCount[key] = (pairCount[key] ?? 0) + h.comparisons
        }

        // Candidate pool excluding blocklist
        let pool = itemIds.filter { !recentBlocklist.contains($0) }
        guard pool.count >= 2 else { return nil }

        // Heuristic: prefer pairs with similar scores (hard decisions),
        // fewer prior comparisons, and not in recent blocklist.
        // Try random samples to find a good one.
        var best: (String, String)?
        var bestScore = -Double.infinity

        let tries = min(maxTries, pool.count * 10)
        for _ in 0..<tries {
            let a = pool.randomElement()!
            var b = pool.randomElement()!
            var guardCount = 0
            while b == a && guardCount < 10 {
                b = pool.randomElement()!
                guardCount += 1
            }
            if a == b { continue }

            let sA = score(a), sB = score(b)
            let closeness = 1.0 / (1.0 + abs(sA - sB)) // 0..1, higher is closer
            let key = PairKey(a, b)
            let seen = Double(pairCount[key] ?? 0)
            let freshness = 1.0 / (1.0 + seen)         // prefer pairs seen fewer times

            // Blend score: tune weights if you like
            let composite = 0.70 * closeness + 0.30 * freshness

            if composite > bestScore {
                bestScore = composite
                best = (a, b)
            }
        }

        return best
    }

    // Unordered pair key
    private struct PairKey: Hashable {
        let x: String
        let y: String
        init(_ a: String, _ b: String) {
            if a < b { x = a; y = b } else { x = b; y = a }
        }
    }
}
