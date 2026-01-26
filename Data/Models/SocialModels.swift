import Foundation

// Defines what a User Profile looks like
struct SocialProfile: Codable, Identifiable, Hashable {
    let id: UUID
    let username: String?
    let fullName: String?
    let avatarUrl: String?
    
    var displayName: String {
        if let f = fullName, !f.isEmpty { return f }
        if let u = username, !u.isEmpty { return "@\(u)" }
        return "Anonymous"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case fullName = "full_name"
        case avatarUrl = "avatar_url"
    }
}

// Defines a "Follow" relationship
struct FollowRecord: Codable {
    let followerId: UUID
    let followingId: UUID
    
    enum CodingKeys: String, CodingKey {
        case followerId = "follower_id"
        case followingId = "following_id"
    }
}
