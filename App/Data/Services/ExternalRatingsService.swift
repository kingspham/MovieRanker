import Foundation

struct ExternalRatings: Sendable, Equatable {
    let imdb: String?
    let metacritic: String?
    let rottenTomatoes: String?
    let plot: String? = nil
}

enum ExternalRatingsService {
    static func fetch(forTitle title: String, year: Int?) async throws -> ExternalRatings {
        // Temporary no-op implementation so the app compiles.
        // Wire OMDb or other sources later.
        return ExternalRatings(imdb: nil, metacritic: nil, rottenTomatoes: nil)
    }
}

