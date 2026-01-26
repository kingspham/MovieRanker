import Foundation

public struct UserProfile: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var username: String?
    public var displayName: String?

    public init(id: String, username: String? = nil, displayName: String? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName
    }
}
