import Foundation
import SwiftData

@Model
final class CustomList {
    @Attribute(.unique) var id: UUID
    var name: String
    var details: String
    var createdAt: Date
    var ownerId: String
    var isPublic: Bool

    // We store a list of Movie IDs.
    // This is safer than a direct relationship for simple lists.
    var movieIDs: [UUID] = []

    init(name: String, details: String = "", ownerId: String, isPublic: Bool = false) {
        self.id = UUID()
        self.name = name
        self.details = details
        self.createdAt = Date()
        self.ownerId = ownerId
        self.isPublic = isPublic
    }
}
