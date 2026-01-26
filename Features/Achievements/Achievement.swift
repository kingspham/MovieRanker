import Foundation
import SwiftData

@Model
final class Achievement {
    var id: UUID
    var ownerId: String
    var key: String          // e.g. "watched_10_movies"
    var title: String
    var detail: String
    var unlockedAt: Date
    var icon: String         // SF Symbol name

    init(id: UUID = UUID(),
         ownerId: String,
         key: String,
         title: String,
         detail: String,
         icon: String,
         unlockedAt: Date = Date()) {
        self.id = id
        self.ownerId = ownerId
        self.key = key
        self.title = title
        self.detail = detail
        self.icon = icon
        self.unlockedAt = unlockedAt
    }
}
