import Foundation
import SwiftData

@Model
final class LogEntry {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var rating: Double?
    var watchedOn: Date?
    var whereWatched: WatchLocation?
    var withWho: String?
    var notes: String?
    var labels: [String]?
    var movie: Movie?
    var show: Show?
    var ownerId: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        rating: Double? = nil,
        watchedOn: Date? = nil,
        whereWatched: WatchLocation? = nil,
        withWho: String? = nil,
        notes: String? = nil,
        labels: [String]? = nil,
        movie: Movie? = nil,
        show: Show? = nil,
        ownerId: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rating = rating
        self.watchedOn = watchedOn
        self.whereWatched = whereWatched
        self.withWho = withWho
        self.notes = notes
        self.labels = labels
        self.movie = movie
        self.show = show
        self.ownerId = ownerId
    }
}
