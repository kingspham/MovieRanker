import Foundation
import Supabase
import SwiftData

struct FriendActivityItem: Identifiable, Equatable {
    let id: UUID            // review id
    let movieID: UUID
    let movieTitle: String
    let body: String
    let authorID: String
    let createdAt: Date
}

@MainActor
final class FriendActivityService {
    static let shared = FriendActivityService(); private init() {}
    private var client: SupabaseClient? { SessionManager.shared.client }

    // MARK: - Decoding helpers for Supabase response
    private struct ReviewRow: Decodable {
        let id: UUID
        let owner_id: String
        let movie_id: UUID
        let body: String
        let created_at: Date
        let movies: MovieRef?
    }

    private struct MovieRef: Decodable {
        let title: String?
    }

    func fetchRecentReviews(friendIDs: Set<String>, limit: Int = 30) async -> [FriendActivityItem] {
        guard let client, !friendIDs.isEmpty else { return [] }
        do {
            // Decode directly to typed rows to avoid casting from Void/Any
            let rows: [ReviewRow] = try await client
                .from("reviews")
                .select("id,owner_id,movie_id,body,created_at,movies(title)")
                .in("owner_id", values: Array(friendIDs))
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value

            return rows.map { row in
                FriendActivityItem(
                    id: row.id,
                    movieID: row.movie_id,
                    movieTitle: row.movies?.title ?? "Unknown",
                    body: row.body,
                    authorID: row.owner_id,
                    createdAt: row.created_at
                )
            }
        } catch {
            return []
        }
    }
}
