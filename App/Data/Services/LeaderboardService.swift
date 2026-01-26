import Foundation
import Combine
import Supabase

struct LeaderboardRow: Identifiable, Equatable {
    var id: String { movieId.uuidString }
    let movieId: UUID
    let title: String
    let posterPath: String?
    let avg100: Double
    let ratingsCount: Int
}

@MainActor
final class LeaderboardService: ObservableObject {
    
    static let shared = LeaderboardService()
    private init() {}

    private var client: SupabaseClient? { SessionManager.shared.client }

    /// Global leaderboard: top movies by avg score, minimum N ratings
    func fetchGlobal(minRatings: Int = 3, limit: Int = 100) async throws -> [LeaderboardRow] {
        guard let client else { return [] }
        // join movie_ratings_agg (agg) with movies (to get title/poster)
        let resp = try await client.from("movie_ratings_agg")
            .select("movie_id,avg100,ratings_count,movies(title,poster_path)")
            .gte("ratings_count", value: minRatings)
            .order("avg100", ascending: false)
            .limit(limit)
            .execute()

        return parseRows(resp.value)
    }

    /// Friends leaderboard: filter scores to friends (computed by joining friends table in a where-in clause)
    func fetchFriends(friendIDs: Set<String>, minRatings: Int = 1, limit: Int = 100) async throws -> [LeaderboardRow] {
        guard let client, !friendIDs.isEmpty else { return [] }

        struct FriendScoreRow: Decodable {
            let movie_id: UUID
            let display100: Double
            let owner_id: String
            let movies: Movie
            struct Movie: Decodable { let title: String; let poster_path: String? }
        }

        let response = try await client
            .from("scores")
            .select("movie_id,display100,movies(title,poster_path),owner_id")
            .in("owner_id", values: Array(friendIDs))
            .execute()

        let raw = try JSONDecoder().decode([FriendScoreRow].self, from: response.data)
        // end manual decode

        // Aggregate client-side
        struct Agg { var sum: Double = 0; var count: Int = 0; var title: String = ""; var poster: String? = nil }
        var map: [UUID: Agg] = [:]

        for row in raw {
            let mid = row.movie_id
            let score = row.display100
            var agg = map[mid] ?? Agg()
            agg.sum += score
            agg.count += 1
            agg.title = row.movies.title
            agg.poster = row.movies.poster_path
            map[mid] = agg
        }

        var rows: [LeaderboardRow] = map.compactMap { (mid, a) in
            guard a.count >= minRatings else { return nil }
            return LeaderboardRow(movieId: mid, title: a.title, posterPath: a.poster, avg100: a.sum / Double(a.count), ratingsCount: a.count)
        }
        rows.sort { $0.avg100 > $1.avg100 }
        if rows.count > limit { rows = Array(rows.prefix(limit)) }
        return rows
    }

    private func parseRows(_ value: Any?) -> [LeaderboardRow] {
        guard let arr = value as? [[String: Any]] else { return [] }
        return arr.compactMap { row in
            guard
                let midStr = row["movie_id"] as? String,
                let mid = UUID(uuidString: midStr),
                let avg = row["avg100"] as? Double,
                let cnt = row["ratings_count"] as? Int
            else { return nil }

            var title = ""
            var poster: String? = nil
            if let m = row["movies"] as? [String: Any] {
                title = (m["title"] as? String) ?? ""
                poster = m["poster_path"] as? String
            }

            return LeaderboardRow(movieId: mid, title: title, posterPath: poster, avg100: avg, ratingsCount: cnt)
        }
    }
}
