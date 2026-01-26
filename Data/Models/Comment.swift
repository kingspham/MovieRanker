import Foundation

struct Comment: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let logId: UUID
    let body: String
    let isSpoiler: Bool // <--- NEW FIELD
    let createdAt: Date
    
    // We fetch the profile with the comment
    let profile: SocialProfile?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case logId = "log_id"
        case body
        case isSpoiler = "is_spoiler" // Maps to database column
        case createdAt = "created_at"
        case profile = "profiles"
    }
}
