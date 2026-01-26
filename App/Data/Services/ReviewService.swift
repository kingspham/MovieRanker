import Foundation
import Supabase
import Combine

@MainActor
final class ReviewService: ObservableObject {
    static let shared = ReviewService()
    private init() {}

    private var client: SupabaseClient? { SessionManager.shared.client }
    private var myId: String?          { SessionManager.shared.userId }

    // In-memory cache to avoid refetching on every cell draw
    @Published private(set) var likeCounts: [UUID: Int] = [:]
    @Published private(set) var likedByMe: Set<UUID> = []

    // MARK: - Read

    func refreshLikes(for reviewIDs: [UUID]) async {
        guard let client, !reviewIDs.isEmpty else { return }
        let ids = reviewIDs.map { $0.uuidString }

        do {
            // Count likes per review
            struct LikeRow: Decodable { let review_id: String }
            let rows: [LikeRow] = try await client
                .from("review_likes")
                .select("review_id")
                .in("review_id", values: ids)
                .execute()
                .value

            var counts: [UUID: Int] = [:]
            for row in rows {
                if let id = UUID(uuidString: row.review_id) {
                    counts[id, default: 0] += 1
                }
            }
            self.likeCounts.merge(counts) { _, new in new }
        } catch {
            // ignore network errors for now
        }

        // Which of these do *I* like?
        if let myId {
            do {
                struct LikeRow: Decodable { let review_id: String }
                let rows: [LikeRow] = try await client
                    .from("review_likes")
                    .select("review_id")
                    .eq("user_id", value: myId)
                    .in("review_id", values: ids)
                    .execute()
                    .value

                let mine: Set<UUID> = Set(rows.compactMap { UUID(uuidString: $0.review_id) })
                likedByMe.formUnion(mine)
            } catch { }
        }
    }

    // MARK: - Write

    func toggleLike(reviewID: UUID) async {
        guard let client, let myId else { return }
        let key = reviewID

        // Optimistic UI
        let wasLiked = likedByMe.contains(key)
        if wasLiked {
            likedByMe.remove(key)
            likeCounts[key, default: 1] -= 1
        } else {
            likedByMe.insert(key)
            likeCounts[key, default: 0] += 1
        }

        do {
            if wasLiked {
                _ = try await client
                    .from("review_likes")
                    .delete()
                    .eq("review_id", value: key.uuidString)
                    .eq("user_id", value: myId)
                    .execute()
            } else {
                _ = try await client
                    .from("review_likes")
                    .insert([["review_id": key.uuidString, "user_id": myId]])
                    .execute()
            }
        } catch {
            // Revert if API fails
            if wasLiked {
                likedByMe.insert(key)
                likeCounts[key, default: 0] += 1
            } else {
                likedByMe.remove(key)
                likeCounts[key, default: 1] -= 1
            }
        }
    }
}

