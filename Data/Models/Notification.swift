import Foundation

struct AppNotification: Decodable, Identifiable {
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
        case id, type, message, body, text, read
        case userId = "user_id"
        case recipientId = "recipient_id"
        case actorId = "actor_id"
        case relatedId = "related_id"
        case createdAtString = "created_at"
        case actor = "profiles" // Joined table
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        message = try container.decode(String.self, forKey: .message)
        read = try container.decode(Bool.self, forKey: .read)
        actorId = try container.decode(UUID.self, forKey: .actorId)
        relatedId = try container.decodeIfPresent(UUID.self, forKey: .relatedId)
        createdAtString = try container.decode(String.self, forKey: .createdAtString)
        actor = try container.decodeIfPresent(SocialProfile.self, forKey: .actor)

        if let user = try container.decodeIfPresent(UUID.self, forKey: .userId) {
            userId = user
        } else {
            userId = try container.decode(UUID.self, forKey: .recipientId)
        }
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
