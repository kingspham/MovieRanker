import Foundation
import SwiftData

enum LocalLeaderboard {
    static func compute(modelContext: ModelContext, minRatings: Int = 1, limit: Int = 100) -> [LeaderboardRow] {
        let movies: [Movie] = (try? modelContext.fetch(FetchDescriptor<Movie>())) ?? []
        let scores: [Score] = (try? modelContext.fetch(FetchDescriptor<Score>())) ?? []

        var map: [UUID: (sum: Double, count: Int, title: String, poster: String?)] = [:]
        for s in scores {
            guard let m = movies.first(where: { $0.id == s.movieID }) else { continue }
            var a = map[m.id] ?? (0, 0, m.title, m.posterPath)
            a.sum += Double(s.display100)
            a.count += 1
            a.title = m.title
            a.poster = m.posterPath
            map[m.id] = a
        }

        var out: [LeaderboardRow] = map.compactMap { (mid, a) in
            guard a.count >= minRatings else { return nil }
            return LeaderboardRow(movieId: mid, title: a.title, posterPath: a.poster, avg100: a.sum / Double(a.count), ratingsCount: a.count)
        }
        out.sort { $0.avg100 > $1.avg100 }
        if out.count > limit { out = Array(out.prefix(limit)) }
        return out
    }
}
