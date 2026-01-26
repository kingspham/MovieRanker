import Foundation
import Supabase
import Combine

@MainActor
final class FriendsService: ObservableObject {
    
    static let shared = FriendsService()

    @Published private(set) var friendIDs: Set<String> = []

    private var client: SupabaseClient? { SessionManager.shared.client }
    private var myId: String? { SessionManager.shared.userId }

    private init() {}

    private struct FriendRow: Decodable {
        let user_id: String
        let friend_id: String
    }

    func refresh() async {
        guard let client, let myId else {
            friendIDs = []
            return
        }
        do {
            let rows: [FriendRow] = try await client
                .from("friends")
                .select()
                .eq("user_id", value: myId)
                .execute()
                .value
            friendIDs = Set(rows.map { $0.friend_id })
        } catch {
            friendIDs = []
        }
    }

    func addFriend(friendId: String) async throws {
        guard let client, let myId else { return }
        _ = try await client.from("friends")
            .insert([["user_id": myId, "friend_id": friendId]])
            .execute()
        await refresh()
    }

    func removeFriend(friendId: String) async throws {
        guard let client, let myId else { return }
        _ = try await client.from("friends")
            .delete()
            .eq("user_id", value: myId)
            .eq("friend_id", value: friendId)
            .execute()
        await refresh()
    }
}
