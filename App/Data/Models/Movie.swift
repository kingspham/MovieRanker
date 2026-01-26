import Foundation
import SwiftData

@Model
final class Movie {
    @Attribute(.unique) var id: UUID
    var title: String
    var year: Int?
    var tmdbID: Int?
    var posterPath: String?
    var genreIDs: [Int]
    var popularity: Double?
    var ownerId: String?
    var createdAt: Date
    var titleLower: String

    init(
        id: UUID = UUID(),
        title: String,
        year: Int? = nil,
        tmdbID: Int? = nil,
        posterPath: String? = nil,
        genreIDs: [Int] = [],
        popularity: Double? = nil,
        ownerId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.tmdbID = tmdbID
        self.posterPath = posterPath
        self.genreIDs = genreIDs
        self.popularity = popularity
        self.ownerId = ownerId
        self.createdAt = Date()
        self.titleLower = title
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
