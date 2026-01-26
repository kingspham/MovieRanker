//
//  PredictionsEngine.swift
//  MovieRanker
//
//  Simple, explainable blend: BTL strength + content similarity.
//  You can replace the similarity with a richer embedding later.
//

import Foundation

public struct ContentFeatures: Codable, Sendable {
    public let genres: Set<String>
    public let directors: Set<String>
    public let cast: Set<String>
    public init(genres: Set<String>, directors: Set<String>, cast: Set<String>) {
        self.genres = genres
        self.directors = directors
        self.cast = cast
    }
}

public enum PredictionsEngine {

    /// Predicts relative preference score for a candidate item.
    /// - Parameters:
    ///   - candidateId: item to score
    ///   - btlStrength: learned BTL strength for each item (id → s_i)
    ///   - features: content features for each item (id → ContentFeatures)
    ///   - likedAnchors: subset of ids the user loves (9–10s) for similarity
    ///   - alpha: blend weight (0..1) between BTL (global) and similarity (personalized)
    /// - Returns: 0..100 predicted “you’ll like this” score
    public static func predictedPreference(
        candidateId: String,
        btlStrength: [String: Double],
        features: [String: ContentFeatures],
        likedAnchors: [String],
        alpha: Double = 0.7
    ) -> Double {
        let s = btlStrength[candidateId] ?? 1.0

        // Normalize BTL to 0..100 for blending
        let (minS, maxS) = minMax(btlStrength.values)
        let btlScaled = maxS > minS ? 100.0 * (s - minS) / (maxS - minS) : 50.0

        // Content similarity vs liked anchors (simple Jaccard blend)
        var sims: [Double] = []
        guard let cand = features[candidateId] else {
            return btlScaled
        }

        for a in likedAnchors {
            guard let f = features[a] else { continue }
            let g = jaccard(cand.genres, f.genres)
            let d = jaccard(cand.directors, f.directors)
            let c = jaccard(cand.cast, f.cast)
            // Heavier weight to genres & directors; tune as desired
            let sim = 0.5*g + 0.3*d + 0.2*c
            sims.append(sim)
        }
        let simAvg = sims.isEmpty ? 0.5 : sims.reduce(0,+)/Double(sims.count)
        let simScaled = 100.0 * simAvg

        let blended = alpha * btlScaled + (1.0 - alpha) * simScaled
        return max(0, min(100, blended))
    }

    private static func minMax(_ xs: [Double]) -> (Double, Double) {
        var lo = Double.greatestFiniteMagnitude
        var hi = -Double.greatestFiniteMagnitude
        for x in xs {
            if x < lo { lo = x }
            if x > hi { hi = x }
        }
        if xs.isEmpty { lo = 0; hi = 1 }
        return (lo, hi)
        }

    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty && b.isEmpty { return 0.0 }
        let inter = a.intersection(b).count
        let union = a.union(b).count
        return union > 0 ? Double(inter) / Double(union) : 0.0
    }
}
