import Foundation

// Genre-based taste model. Pure Swift, on-device.
enum Recommender {
    // Map of TMDb Genre id -> weight (positive = you like it, negative = you avoid it)
    static func userGenreWeights(seen: [(genreIDs: [Int], score100: Double)]) -> [Int: Double] {
        var weights: [Int: Double] = [:]
        for item in seen {
            guard !item.genreIDs.isEmpty else { continue }
            // Center score at 50, normalize to [-1, 1]
            let centered = (item.score100 - 50.0) / 50.0
            // Spread weight equally across that movie's genres
            let per = centered / Double(item.genreIDs.count)
            for gid in item.genreIDs {
                weights[gid, default: 0] += per
            }
        }
        return weights
    }

    // Predict a score 1–100 for a candidate movie given user weights.
    static func predictScore100(genreIDs: [Int], weights: [Int: Double]) -> Int {
        guard !genreIDs.isEmpty else { return 50 }
        var dot: Double = 0
        for gid in genreIDs {
            dot += weights[gid, default: 0]
        }
        // dot is roughly in [-k, +k], map to [1, 100]
        // Clamp softly: 50 + 40 * tanh(dot)
        let raw = 50.0 + 40.0 * tanh(dot)
        return max(1, min(100, Int(raw.rounded())))
    }
}
