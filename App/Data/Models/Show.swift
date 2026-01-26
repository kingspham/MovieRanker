import Foundation
import SwiftData

@Model
final class Show {
    @Attribute(.unique) var id: UUID
    var title: String
    var yearStart: Int?  // <- Changed from 'year'
    var tmdbID: Int?
    var posterPath: String?
    var genreIDs: [Int]?
    var popularity: Double?
    var ownerId: String
    var titleLower: String?

    init(
        id: UUID = UUID(),
        title: String,
        yearStart: Int? = nil,  // <- Changed
        tmdbID: Int? = nil,
        posterPath: String? = nil,
        genreIDs: [Int]? = nil,
        popularity: Double? = nil,
        ownerId: String
    ) {
        self.id = id
        self.title = title
        self.yearStart = yearStart  // <- Changed
        self.tmdbID = tmdbID
        self.posterPath = posterPath
        self.genreIDs = genreIDs
        self.popularity = popularity
        self.ownerId = ownerId
        self.titleLower = title
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
