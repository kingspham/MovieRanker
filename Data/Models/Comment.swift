import Foundation

struct Comment: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let logId: UUID
    let body: String
    let isSpoiler: Bool

    // We fetch the profile with the comment
    let profile: SocialProfile?

    // Store raw string, convert to Date in computed property
    private let createdAtString: String

    var createdAt: Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAtString) ?? Date()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case logId = "log_id"
        case body
        case isSpoiler = "is_spoiler"
        case createdAtString = "created_at"
        case profile = "profiles"
    }
}
