import Foundation
import SwiftData
import Combine

@MainActor
final class TasteModel: ObservableObject {
    private var genreWeights: [Int: Double] = [:]

    func train(from context: ModelContext) {
        let items: [UserItem] = context.fetchAll()
        let scores: [Score] = context.fetchAll()
        let _: [Movie] = context.fetchAll()

        let scoreByID = Dictionary(uniqueKeysWithValues: scores.map { ($0.movieID, $0.display100) })
        
        var genreCounts: [Int: (sum: Double, count: Int)] = [:]

        for item in items where item.state == .seen {
            guard let movie = item.movie,
                  let score = scoreByID[movie.id] else { continue }
            
            let genres = movie.genreIDs
            guard !genres.isEmpty else { continue }

            for gid in genres {
                var entry = genreCounts[gid] ?? (0, 0)
                entry.sum += Double(score)
                entry.count += 1
                genreCounts[gid] = entry
            }
        }

        genreWeights = genreCounts.mapValues { $0.sum / Double($0.count) }
    }

    func predict(for movie: Movie) -> Double {
        let genres = movie.genreIDs
        guard !genres.isEmpty else { return 50.0 }
        
        let matches = genres.compactMap { genreWeights[$0] }
        guard !matches.isEmpty else { return 50.0 }
        
        return matches.reduce(0, +) / Double(matches.count)
    }
}
