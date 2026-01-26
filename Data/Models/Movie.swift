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
    var tags: [String]
    var mediaType: String
    var popularity: Double?
    var ownerId: String?
    var createdAt: Date
    var titleLower: String
    
    // Extra fields
    var authors: [String]?
    var pageCount: Int?
    var seasonNumber: Int?
    var watchProviders: [String]?
    
    // External Ratings
    var imdbRating: String?
    var metaScore: String?
    var rottenTomatoesRating: String?

    // --- CRITICAL FIX: Inverse Relationship ---
    // This creates a stable link between Movie and UserItem
    @Relationship(deleteRule: .cascade, inverse: \UserItem.movie)
    var userItems: [UserItem]? = []

    init(
        id: UUID = UUID(),
        title: String,
        year: Int? = nil,
        tmdbID: Int? = nil,
        posterPath: String? = nil,
        genreIDs: [Int] = [],
        tags: [String] = [],
        mediaType: String = "movie",
        popularity: Double? = nil,
        ownerId: String? = nil,
        authors: [String]? = nil,
        pageCount: Int? = nil,
        seasonNumber: Int? = nil,
        watchProviders: [String]? = nil,
        imdbRating: String? = nil,
        metaScore: String? = nil,
        rottenTomatoesRating: String? = nil
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.tmdbID = tmdbID
        self.posterPath = posterPath
        self.genreIDs = genreIDs
        self.tags = tags
        self.mediaType = mediaType
        self.popularity = popularity
        self.ownerId = ownerId
        self.createdAt = Date()
        self.titleLower = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.authors = authors
        self.pageCount = pageCount
        self.seasonNumber = seasonNumber
        self.watchProviders = watchProviders
        self.imdbRating = imdbRating
        self.metaScore = metaScore
        self.rottenTomatoesRating = rottenTomatoesRating
    }
}
