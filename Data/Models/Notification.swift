import Foundation

struct AppNotification: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let actorId: UUID
    let type: String // 'like', 'comment', 'follow'
    let message: String
    let relatedId: UUID?
    let read: Bool
    let createdAt: Date
    
    // The person who triggered it (Joined)
    let actor: SocialProfile?
    
    enum CodingKeys: String, CodingKey {
        case id, type, message, read
        case userId = "user_id"
        case actorId = "actor_id"
        case relatedId = "related_id"
        case createdAt = "created_at"
        case actor = "profiles" // Joined table
    }
}
