import Foundation
import SwiftData
import Combine

@MainActor
final class StatsViewModel: ObservableObject {
    @Published var headerSummary: String = ""
    @Published var totalWatched: Int = 0
    @Published var totalWatchlist: Int = 0
    @Published var avgRating: Double = 0
    @Published var avgElo: Double = 0
    @Published var recentRatings: [(date: Date, rating: Double)] = []
    @Published var topGenres: [String] = []

    func load(from context: ModelContext) {
        let items: [UserItem] = context.fetchAll()
        let scores: [Score] = context.fetchAll()
        let logs: [LogEntry] = context.fetchAll()
        let _: [Movie] = context.fetchAll()

        totalWatched = items.filter { $0.state == .seen }.count
        totalWatchlist = items.filter { $0.state == .watchlist }.count

        if !scores.isEmpty {
            avgElo = scores.map { Double($0.display100) }.reduce(0, +) / Double(scores.count)
        }

        // Recent ratings from logs
        recentRatings = logs
            .compactMap { log -> (Date, Double)? in
                guard let r = log.rating else { return nil }
                return (log.watchedOn ?? log.createdAt, Double(r))
            }
            .sorted { $0.0 > $1.0 }
            .prefix(10)
            .map { $0 }

        if !recentRatings.isEmpty {
            avgRating = recentRatings.map { $0.rating }.reduce(0, +) / Double(recentRatings.count)
        }

        // Top genres
        var genreCounts: [Int: Int] = [:]
        for item in items where item.state == .seen {
            if let movie = item.movie {
                let genres = movie.genreIDs
                for gid in genres {
                    genreCounts[gid, default: 0] += 1
                }
            }
        }

        topGenres = genreCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { genreIDToName($0.key) }

        headerSummary = "You've watched \(totalWatched) movies"
    }

    private func genreIDToName(_ id: Int) -> String {
        let map: [Int: String] = [
            28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy",
            80: "Crime", 99: "Documentary", 18: "Drama", 10751: "Family",
            14: "Fantasy", 36: "History", 27: "Horror", 10402: "Music",
            9648: "Mystery", 10749: "Romance", 878: "Sci-Fi", 53: "Thriller",
            10752: "War", 37: "Western"
        ]
        return map[id] ?? "Other"
    }
}
