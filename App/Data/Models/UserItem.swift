import Foundation
import SwiftData

@Model
final class UserItem {
    enum State: String, Codable {
        case watchlist
        case seen
    }
    
    @Attribute(.unique) var id: UUID
    var movie: Movie?
    var show: Show?
    var state: State
    var ownerId: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        movie: Movie? = nil,
        show: Show? = nil,
        state: State,
        ownerId: String?
    ) {
        self.id = id
        self.movie = movie
        self.show = show
        self.state = state
        self.ownerId = ownerId
        self.createdAt = Date()
    }
}
