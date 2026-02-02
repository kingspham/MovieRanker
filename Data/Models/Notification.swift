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

    // Custom decoder to handle missing fields gracefully
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        actorId = try container.decode(UUID.self, forKey: .actorId)
        type = try container.decode(String.self, forKey: .type)
        // Make message optional with a default based on type
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? "New \(type) notification"
        relatedId = try container.decodeIfPresent(UUID.self, forKey: .relatedId)
        read = try container.decodeIfPresent(Bool.self, forKey: .read) ?? false
        createdAtString = try container.decode(String.self, forKey: .createdAtString)
        actor = try container.decodeIfPresent(SocialProfile.self, forKey: .actor)
    }

    // Private init for creating copies with enriched data
    private init(id: UUID, userId: UUID, actorId: UUID, type: String, message: String,
                 relatedId: UUID?, read: Bool, createdAtString: String, actor: SocialProfile?) {
        self.id = id
        self.userId = userId
        self.actorId = actorId
        self.type = type
        self.message = message
        self.relatedId = relatedId
        self.read = read
        self.createdAtString = createdAtString
        self.actor = actor
    }

    /// Create a copy of this notification with the given actor profile
    func withActor(_ profile: SocialProfile) -> AppNotification {
        AppNotification(
            id: id,
            userId: userId,
            actorId: actorId,
            type: type,
            message: message,
            relatedId: relatedId,
            read: read,
            createdAtString: createdAtString,
            actor: profile
        )
    }
}
