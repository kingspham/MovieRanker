import Foundation

struct AppNotification: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let actorId: UUID
    let type: String // 'like', 'comment', 'follow'
    let message: String
    let relatedId: UUID?
    let read: Bool

    // The person who triggered it (Joined)
    let actor: SocialProfile?

    // Store raw string, convert to Date in computed property
    private let createdAtString: String

    var createdAt: Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAtString) ?? Date()
    }

    enum CodingKeys: String, CodingKey {
        case id, type, message, read
        case userId = "user_id"
        case actorId = "actor_id"
        case relatedId = "related_id"
        case createdAtString = "created_at"
        case actor = "profiles" // Joined table
    }
}
