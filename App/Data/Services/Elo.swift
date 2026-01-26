import Foundation

/// Lightweight Elo system tuned for 0–100 display scores.
enum Elo {
    struct Rating { var value: Double } // internal rating space

    /// Convert stored display score (0–100) to Elo internal (~1000–2000).
    static func toInternal(_ display: Int) -> Rating {
        let clamped = max(0, min(100, display))
        // Map 0…100 -> 1000…2000 (linear)
        return Rating(value: 1000.0 + (Double(clamped) * 10.0))
    }

    /// Convert internal rating back to display 0…100.
    static func toDisplay(_ rating: Rating) -> Int {
        let v = (rating.value - 1000.0) / 10.0
        return Int(max(0.0, min(100.0, v)).rounded())
    }

    /// Update winner/loser ratings.
    /// K controls how fast scores move. 16–40 is reasonable.
    static func update(winner: Rating, loser: Rating, K: Double = 24) -> (winner: Rating, loser: Rating) {
        let expectedW = 1.0 / (1.0 + pow(10.0, (loser.value - winner.value) / 400.0))
        let expectedL = 1.0 - expectedW
        let newW = winner.value + K * (1.0 - expectedW)
        let newL = loser.value + K * (0.0 - expectedL)
        return (Rating(value: newW), Rating(value: newL))
    }
}
