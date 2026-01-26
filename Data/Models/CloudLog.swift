import Foundation

struct CloudLog: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let tmdbId: Int?
    let title: String
    let year: Int?
    let posterPath: String?
    let mediaType: String?
    let score: Int?
    let notes: String?
    let platform: String?
    let genres: [String]?
    
    private let watchedOnString: String?
    private let createdAtString: String
    
    let profile: SocialProfile?
    
    // NEW: Interaction Data
    // These come from Supabase joins/counts
    let likes: [LikeStub]?
    let comments: [CommentStub]?
    
    struct LikeStub: Codable { let user_id: UUID }
    struct CommentStub: Codable { let id: UUID }
    
    var likeCount: Int { likes?.count ?? 0 }
    var commentCount: Int { comments?.count ?? 0 }
    
    // Helper to check if I liked it
    func isLiked(by myUserId: String) -> Bool {
        guard let uuid = UUID(uuidString: myUserId) else { return false }
        return likes?.contains { $0.user_id == uuid } ?? false
    }
    
    var watchedOn: Date? {
        guard let s = watchedOnString else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: s)
    }
    
    var createdAt: Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAtString) ?? Date()
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, year, score, notes, platform, genres
        case userId = "user_id"
        case tmdbId = "tmdb_id"
        case posterPath = "poster_path"
        case mediaType = "media_type"
        case watchedOnString = "watched_on"
        case createdAtString = "created_at"
        case profile = "profiles"
        case likes = "likes"         // joined table
        case comments = "comments"   // joined table
    }
}
