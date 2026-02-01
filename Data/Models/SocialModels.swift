import Foundation

// Defines what a User Profile looks like
struct SocialProfile: Codable, Identifiable, Hashable {
    let id: UUID
    let username: String?
    let fullName: String?
    let avatarUrl: String?

    // User favorites (optional - requires DB columns)
    let favoriteMovie: String?
    let favoriteShow: String?
    let favoriteBook: String?
    let favoritePodcast: String?
    let homeCity: String?
    let bio: String?

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
        case favoriteMovie = "favorite_movie"
        case favoriteShow = "favorite_show"
        case favoriteBook = "favorite_book"
        case favoritePodcast = "favorite_podcast"
        case homeCity = "home_city"
        case bio
    }

    // Custom decoder to handle missing fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        fullName = try container.decodeIfPresent(String.self, forKey: .fullName)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        favoriteMovie = try container.decodeIfPresent(String.self, forKey: .favoriteMovie)
        favoriteShow = try container.decodeIfPresent(String.self, forKey: .favoriteShow)
        favoriteBook = try container.decodeIfPresent(String.self, forKey: .favoriteBook)
        favoritePodcast = try container.decodeIfPresent(String.self, forKey: .favoritePodcast)
        homeCity = try container.decodeIfPresent(String.self, forKey: .homeCity)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
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
