import Foundation
import SwiftData

enum SnapshotService {
    /// Record a snapshot for a movie score.
    static func recordMovie(_ movie: Movie, score: Double, ownerId: String, context: ModelContext) {
        let snap = ScoreSnapshot(ownerId: ownerId, itemID: movie.id, kind: .movie, score: score, createdAt: Date())
        context.insert(snap)
        SD.save(context)
    }

    /// Record a snapshot for a show score.
    static func recordShow(_ show: Show, score: Double, ownerId: String, context: ModelContext) {
        let snap = ScoreSnapshot(ownerId: ownerId, itemID: show.id, kind: .show, score: score, createdAt: Date())
        context.insert(snap)
        SD.save(context)
    }
}
