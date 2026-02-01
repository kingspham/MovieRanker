import Foundation
import Supabase
import Combine

@MainActor
final class SocialService: ObservableObject {
    static let shared = SocialService()
    private var client: SupabaseClient { AuthService.shared.client }
    
    @Published var followingIDs: Set<UUID> = []
    
    func searchUsers(query: String) async throws -> [SocialProfile] {
        guard !query.isEmpty else { return [] }
        return try await client.from("profiles").select().ilike("username", pattern: "%\(query)%").limit(20).execute().value
    }
    
    // MARK: - Follow / Unfollow (Accepts String)
    func follow(targetId: String) async throws {
        guard let currentId = client.auth.currentUser?.id,
              let targetUUID = UUID(uuidString: targetId) else { return }
        
        let record = FollowRecord(followerId: currentId, followingId: targetUUID)
        try await client.from("follows").insert(record).execute()
        followingIDs.insert(targetUUID)
    }
    
    func unfollow(targetId: String) async throws {
        guard let currentId = client.auth.currentUser?.id,
              let targetUUID = UUID(uuidString: targetId) else { return }
        try await client.from("follows").delete().eq("follower_id", value: currentId).eq("following_id", value: targetUUID).execute()
        followingIDs.remove(targetUUID)
    }
    
    func loadFollowing() async {
        guard let currentId = client.auth.currentUser?.id else { return }
        struct FollowRow: Decodable { let following_id: UUID }
        do {
            let rows: [FollowRow] = try await client.from("follows").select("following_id").eq("follower_id", value: currentId).execute().value
            self.followingIDs = Set(rows.map { $0.following_id })
        } catch { print("Error loading following: \(error)") }
    }
    
    // MARK: - Profile Stats (Accepts String)
    func getFollowCounts(userId: String) async -> (followers: Int, following: Int) {
        async let followers = try? client.from("follows").select("*", head: true, count: .exact).eq("following_id", value: userId).execute().count
        async let following = try? client.from("follows").select("*", head: true, count: .exact).eq("follower_id", value: userId).execute().count
        return (await followers ?? 0, await following ?? 0)
    }
    
    func fetchFollowers(userId: String) async -> [SocialProfile] {
        struct Row: Decodable { let follower_id: UUID }
        guard let rows: [Row] = try? await client.from("follows").select("follower_id").eq("following_id", value: userId).execute().value else { return [] }
        let ids = rows.map { $0.follower_id }
        if ids.isEmpty { return [] }
        return (try? await client.from("profiles").select().in("id", values: ids).execute().value) ?? []
    }
    
    func fetchFollowing(userId: String) async -> [SocialProfile] {
        struct Row: Decodable { let following_id: UUID }
        guard let rows: [Row] = try? await client.from("follows").select("following_id").eq("follower_id", value: userId).execute().value else { return [] }
        let ids = rows.map { $0.following_id }
        if ids.isEmpty { return [] }
        return (try? await client.from("profiles").select().in("id", values: ids).execute().value) ?? []
    }
    
    func updateProfile(username: String, fullName: String) async throws {
        guard let currentId = client.auth.currentUser?.id else { return }
        struct UpdatePayload: Encodable { let username: String; let full_name: String }
        try await client.from("profiles").update(UpdatePayload(username: username, full_name: fullName)).eq("id", value: currentId).execute()
    }

    func updateFullProfile(
        username: String,
        fullName: String,
        bio: String?,
        favoriteMovie: String?,
        favoriteShow: String?,
        favoriteBook: String?,
        favoritePodcast: String?,
        homeCity: String?
    ) async throws {
        guard let currentId = client.auth.currentUser?.id else { return }
        struct UpdatePayload: Encodable {
            let username: String
            let full_name: String
            let bio: String?
            let favorite_movie: String?
            let favorite_show: String?
            let favorite_book: String?
            let favorite_podcast: String?
            let home_city: String?
        }
        let payload = UpdatePayload(
            username: username,
            full_name: fullName,
            bio: bio?.isEmpty == true ? nil : bio,
            favorite_movie: favoriteMovie?.isEmpty == true ? nil : favoriteMovie,
            favorite_show: favoriteShow?.isEmpty == true ? nil : favoriteShow,
            favorite_book: favoriteBook?.isEmpty == true ? nil : favoriteBook,
            favorite_podcast: favoritePodcast?.isEmpty == true ? nil : favoritePodcast,
            home_city: homeCity?.isEmpty == true ? nil : homeCity
        )
        try await client.from("profiles").update(payload).eq("id", value: currentId).execute()
    }
    
    func getMyProfile() async throws -> SocialProfile? {
        guard let currentId = client.auth.currentUser?.id else { return nil }
        let response: [SocialProfile] = try await client.from("profiles").select().eq("id", value: currentId).execute().value
        return response.first
    }
}
