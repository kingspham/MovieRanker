import Foundation
import SwiftData

// Unified result used by the search UI (movies only for now)
struct UnifiedSearchResult: Identifiable, Equatable {
    enum Kind { case movie }
    let kind: Kind = .movie

    // Remote (TMDb)
    let tmdbId: Int?
    let title: String
    let year: Int?
    let posterPath: String?

    // Local (SwiftData)
    let localId: UUID?
    let yourScore: Double?
    let watchState: UserItem.State
    var localMovie: Movie?

    var isInLibrary: Bool { localId != nil }
    var id: String { localId?.uuidString ?? "movie:\(tmdbId ?? -1):\(title)" }

    static func == (lhs: UnifiedSearchResult, rhs: UnifiedSearchResult) -> Bool { lhs.id == rhs.id }
}

@MainActor
final class SearchService {
    static let shared = SearchService()
    private init() {}

    // MARK: - Public search

    func run(query: String, context: ModelContext) async -> [UnifiedSearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        // 1) Local (movies)
        let localMovies = fetchLocalMovies(matching: q, context: context)
        let localResults: [UnifiedSearchResult] = localMovies.map { m in
            UnifiedSearchResult(
                tmdbId: m.tmdbID,
                title: m.title,
                year: m.year,
                posterPath: m.posterPath,
                localId: m.id,
                yourScore: nil,
                watchState: existingWatchState(for: m, context: context),
                localMovie: m
            )
        }

        // 2) Remote (TMDb) — dedupe by tmdbId against local
        var remoteResults: [UnifiedSearchResult] = []
        do {
            let client = try TMDbClient()
            let page = try await client.searchMovies(query: q)
            for r in page.results {
                if localResults.contains(where: { $0.tmdbId == r.id }) { continue }
                remoteResults.append(
                    UnifiedSearchResult(
                        tmdbId: r.id,
                        title: r.title,
                        year: r.year,
                        posterPath: r.posterPath,
                        localId: nil,
                        yourScore: nil,
                        watchState: .watchlist,
                        localMovie: nil
                    )
                )
            }
        } catch {
            print("[SearchService] TMDb search failed:", error.localizedDescription)
        }

        return localResults + remoteResults
    }

    // MARK: - Quick actions

    func addToLibraryFromTMDb(result: UnifiedSearchResult, context: ModelContext, ownerId: String?) {
        guard result.localId == nil, let tmdbId = result.tmdbId else { return }

        let owner = ownerId ?? SessionManager.shared.userId ?? "unknown"
        let movie = Movie(
            title: result.title,
            year: result.year,
            tmdbID: tmdbId,
            posterPath: result.posterPath,
            genreIDs: [],
            ownerId: owner
        )
        context.insert(movie)

        // Seed a watchlist entry so it appears in "Your List"
        let ui = UserItem(movie: movie, state: .watchlist, ownerId: owner)
        context.insert(ui)

        SD.save(context)
    }

    func toggleWatchState(movie: Movie, context: ModelContext) {
        let movieID = movie.id
        let pred = #Predicate<UserItem> { $0.movie?.id == movieID }
        let fetch = FetchDescriptor<UserItem>(predicate: pred)

        if let items = try? context.fetch(fetch), let item = items.first {
            item.state = (item.state == .watchlist) ? .seen : .watchlist
        } else {
            let ui = UserItem(movie: movie, state: .seen, ownerId: SessionManager.shared.userId ?? "unknown")
            context.insert(ui)
        }

        SD.save(context)
    }

    // MARK: - Helpers

    private func existingWatchState(for movie: Movie, context: ModelContext) -> UserItem.State {
        let movieID = movie.id
        let pred = #Predicate<UserItem> { $0.movie?.id == movieID }
        let fetch = FetchDescriptor<UserItem>(predicate: pred)
        if let items = try? context.fetch(fetch), let item = items.first {
            return item.state
        }
        return .watchlist
    }

    private func fetchLocalMovies(matching q: String, context: ModelContext) -> [Movie] {
        let pred = #Predicate<Movie> { $0.title.localizedStandardContains(q) }
        let desc = FetchDescriptor<Movie>(predicate: pred)
        return (try? context.fetch(desc)) ?? []
    }
}
