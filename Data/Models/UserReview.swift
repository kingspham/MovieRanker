import Foundation
import SwiftData

@Model
final class UserReview {
    @Attribute(.unique) var id: UUID
    var body: String
    var rating: Int?
    var ownerId: String?
    var movie: Movie?
    // REMOVED: var show: Show?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        body: String,
        rating: Int? = nil,
        ownerId: String? = nil,
        movie: Movie? = nil,
        // REMOVED: show: Show? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.body = body
        self.rating = rating
        self.ownerId = ownerId
        self.movie = movie
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
