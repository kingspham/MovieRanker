//
//  RankingEngine.swift
//  MovieRanker
//
//  Bradley–Terry–Luce pairwise ranking with MM (minorize–maximize) updates.
//  Handles weighted outcomes and optional tie handling.
//  Drop-in, no dependencies.
//

import Foundation

// MARK: - Public Types

public struct BTLItem: Hashable, Codable, Sendable {
    public let id: String      // Use your TMDb id string, or any stable id
    public init(id: String) { self.id = id }
}

public struct BTLComparison: Codable, Sendable {
    public let winnerId: String
    public let loserId: String
    /// Optional weight for intensity (“slightly” = 1.0, “more” = 1.5, “much more” = 2.0, etc.)
    public let weight: Double
    /// Optional tie support: if true, counts half-win to each (rarely needed; default false)
    public let isTie: Bool

    public init(winnerId: String, loserId: String, weight: Double = 1.0, isTie: Bool = false) {
        self.winnerId = winnerId
        self.loserId = loserId
        self.weight = max(0.0, weight)
        self.isTie = isTie
    }
}

public struct BTLScore: Codable, Sendable {
    public let id: String
    /// Positive real strength s_i (not log). Larger = better.
    public let strength: Double
    /// Convenience 0–100 scaling (monotone transform for UI)
    public let scaled0to100: Double
}

public struct BTLFitConfig: Sendable {
    public var maxIterations: Int = 200
    public var tolerance: Double = 1e-6
    /// Smoothing prior to avoid zeros and disconnected graphs
    public var priorStrength: Double = 1.0
    /// If true, normalize strengths so geometric mean = 1
    public var normalizeGeometricMean: Bool = true
    public init() {}
}

// MARK: - Engine

public enum BTLEngine {

    /// Compute BTL strengths from pairwise data using an MM update.
    /// - Parameters:
    ///   - items: universe of items you want scores for
    ///   - comparisons: list of pairwise outcomes (weighted allowed)
    ///   - config: iteration + smoothing config
    /// - Returns: array of BTLScore (one per item), sorted by strength descending
    public static func fit(
        items: [BTLItem],
        comparisons: [BTLComparison],
        config: BTLFitConfig = .init()
    ) -> [BTLScore] {

        // Build index mapping
        let ids = items.map(\.id)
        let n = ids.count
        var indexOf: [String:Int] = [:]
        for (i, id) in ids.enumerated() { indexOf[id] = i }

        // Matrices of wins and totals between pairs
        var w = Array(repeating: Array(repeating: 0.0, count: n), count: n)   // w_ij = times i beat j (weighted)
        var nMat = Array(repeating: Array(repeating: 0.0, count: n), count: n) // n_ij = total matches of i vs j (weighted)

        var totalGraphsInvolved = Set<String>()

        // Populate from comparisons
        for c in comparisons {
            guard let wi = indexOf[c.winnerId], let li = indexOf[c.loserId] else { continue }
            let wt = max(0.0, c.weight)

            if c.isTie {
                // half to each side
                w[wi][li] += 0.5 * wt
                w[li][wi] += 0.5 * wt
                nMat[wi][li] += wt
                nMat[li][wi] += wt
            } else {
                w[wi][li] += wt
                nMat[wi][li] += wt
                nMat[li][wi] += wt
            }
            totalGraphsInvolved.insert(c.winnerId)
            totalGraphsInvolved.insert(c.loserId)
        }

        // Prior: add a small symmetric count to connect graph and avoid zeros
        // priorStrength acts like each pair has priorStrength "virtual ties"
        if config.priorStrength > 0 {
            for i in 0..<n {
                for j in (i+1)..<n {
                    w[i][j] += 0.5 * config.priorStrength
                    w[j][i] += 0.5 * config.priorStrength
                    nMat[i][j] += config.priorStrength
                    nMat[j][i] += config.priorStrength
                }
            }
        }

        // Initialize strengths uniformly
        var s = Array(repeating: 1.0, count: n)

        // MM iterations: s_i^{new} = w_i / sum_j n_ij / (s_i + s_j)
        var iter = 0
        var delta = Double.infinity

        while iter < config.maxIterations && delta > config.tolerance {
            var newS = s
            delta = 0.0

            for i in 0..<n {
                var wiSum = 0.0
                var denom = 0.0
                for j in 0..<n where j != i {
                    wiSum += w[i][j]
                    let nij = nMat[i][j]
                    if nij > 0 {
                        denom += nij / (s[i] + s[j])
                    }
                }
                // Guard: if denom is ~0 (no matches), keep old value
                if denom > 0 {
                    let updated = wiSum / denom
                    // avoid collapse to zero
                    newS[i] = max(updated, 1e-12)
                } else {
                    newS[i] = s[i]
                }
            }

            // Optional normalization for stability (geometric mean = 1)
            if config.normalizeGeometricMean {
                let logMean = newS.map { log($0) }.reduce(0, +) / Double(n)
                let scale = exp(-logMean)
                for i in 0..<n { newS[i] *= scale }
            }

            // compute max change
            for i in 0..<n {
                delta = max(delta, abs(newS[i] - s[i]))
            }
            s = newS
            iter += 1
        }

        // Map to scores + 0–100 scaling for UI
        let maxS = s.max() ?? 1.0
        let minS = s.min() ?? 0.0
        let denom = max(1e-9, maxS - minS)

        var results: [BTLScore] = []
        results.reserveCapacity(n)
        for i in 0..<n {
            let scaled = 100.0 * (s[i] - minS) / denom
            results.append(BTLScore(id: ids[i], strength: s[i], scaled0to100: scaled))
        }
        results.sort { $0.strength > $1.strength }
        return results
    }
}
