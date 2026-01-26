//
//  SearchView.swift
//  MovieRanker
//

import SwiftUI
import SwiftData

// MARK: - Domain switch

enum SearchDomain: String, CaseIterable, Identifiable {
    case movies = "Movies"
    case shows  = "Shows"
    var id: String { rawValue }
}

// MARK: - View

struct SearchView: View {
    @Environment(\.modelContext) private var context

    // UI state
    @State private var domain: SearchDomain = .movies
    @State private var query: String = ""
    @State private var isLoading: Bool = false
    @State private var errorText: String? = nil

    @State private var popular: [TMDbMovie] = []
    @State private var isLoadingPopular: Bool = false

    // New states for top picks and trending shows
    @State private var topPicks: [TMDbMovie] = []
    @State private var trendingShows: [TMDbShow] = []
    @State private var isLoadingTrendingShows: Bool = false

    private let quickFilterGenres: [(id: Int, name: String)] = [
        (28, "Action"), (35, "Comedy"), (18, "Drama"), (878, "Sci-Fi"), (27, "Horror")
    ]

    // Results
    @State private var movieResults: [MovieHit] = []
    @State private var showResults: [TMDbShow] = []

    // Prediction model (built on demand)
    @StateObject private var tasteModel = TasteModel()
    @ObservedObject private var recentStore = RecentSearchStore.shared
    @State private var watchlistTMDbIDs: Set<Int> = []

    // Debouncer (you already have this in your project)
    private let debouncer = Debouncer()

    // Precomputed trimmed query to keep view builder simple
    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Results
                List {
                    let trimmed = trimmedQuery

                    trendingMoviesSection(trimmed: trimmed)
                    recentSearchesSection(trimmed: trimmed)
                    quickFiltersSection(trimmed: trimmed)
                    topPicksSection(trimmed: trimmed)
                    trendingShowsSection(trimmed: trimmed)
                    loadingOrEmptySection(trimmed: trimmed)

                    if domain == .movies {
                        movieResultsSection()
                    } else {
                        showResultsSection()
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Search")
#if os(iOS)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
#else
            .searchable(text: $query)
#endif
            .searchScopes($domain) {
                Text("Movies").tag(SearchDomain.movies)
                Text("Shows").tag(SearchDomain.shows)
            }
            .searchSuggestions {
                if trimmedQuery.isEmpty {
                    if !recentStore.recent.isEmpty {
                        ForEach(recentStore.recent, id: \.self) { term in
                            Button(term) {
                                query = term
                                Task { await scheduleSearch() }
                            }
                        }
                    }
                    ForEach(quickFilterGenres, id: \.id) { g in
                        Button(g.name) {
                            Task { await runGenreQuickFilter(g.id) }
                        }
                    }
                }
            }
            .onChange(of: domain) { _, _ in
                Task { await scheduleSearch() }
            }
            .onChange(of: query) { _, _ in
                Task { await scheduleSearch() }
            }
            .task { await loadPopularIfNeeded() }
            .task { await loadTrendingShowsIfNeeded() }
            .task { refreshWatchlistCache() }
        }
    }

    // MARK: - View Sections

    @ViewBuilder
    private func trendingMoviesSection(trimmed: String) -> some View {
        if trimmed.isEmpty && errorText == nil && domain == .movies {
            Section(header: HStack {
                Text("Trending Now")
                if isLoadingPopular {
                    Spacer()
                    ProgressView()
                }
            }) {
                if popular.isEmpty && !isLoadingPopular {
                    Button {
                        Task { await loadPopularIfNeeded() }
                    } label: {
                        Label("Load Trending", systemImage: "arrow.clockwise")
                    }
                } else {
                    ForEach(popular, id: \.id) { m in
                        NavigationLink {
                            MovieInfoView(tmdb: m).modelContext(context)
                        } label: {
                            MovieResultRow(
                                title: m.title,
                                subtitle: m.year.map(String.init),
                                posterPath: m.posterPath,
                                predicted: nil
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recentSearchesSection(trimmed: String) -> some View {
        if trimmed.isEmpty && !recentStore.recent.isEmpty {
            Section(header: Text("Recent Searches")) {
                ForEach(recentStore.recent, id: \.self) { term in
                    Button {
                        query = term
                        Task { await scheduleSearch() }
                    } label: {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)
                            Text(term)
                            Spacer()
                        }
                    }
                }
                Button(role: .destructive) {
                    recentStore.clear()
                } label: {
                    Label("Clear Recent", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder 
    private func quickFiltersSection(trimmed: String) -> some View {
        if trimmed.isEmpty && domain == .movies {
            Section(header: Text("Quick Filters")) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickFilterGenres, id: \.id) { g in
                            Button {
                                Task { await runGenreQuickFilter(g.id) }
                            } label: {
                                Text(g.name)
                                    .font(.caption).bold()
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func topPicksSection(trimmed: String) -> some View {
        if trimmed.isEmpty && !topPicks.isEmpty && domain == .movies && hasEnoughHistory() {
            Section(header: Text("Top Picks For You")) {
                ForEach(topPicks, id: \.id) { m in
                    NavigationLink { MovieInfoView(tmdb: m).modelContext(context) } label: {
                        MovieResultRow(
                            title: m.title,
                            subtitle: m.year.map(String.init),
                            posterPath: m.posterPath,
                            predicted: tasteModel.predict(for: ghostMovie(from: m))
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func trendingShowsSection(trimmed: String) -> some View {
        if trimmed.isEmpty && domain == .shows {
            Section(header: HStack { Text("Trending Shows"); if isLoadingTrendingShows { Spacer(); ProgressView() } }) {
                if trendingShows.isEmpty && !isLoadingTrendingShows {
                    Button {
                        Task { await loadTrendingShowsIfNeeded() }
                    } label: { Label("Load Trending", systemImage: "arrow.clockwise") }
                } else {
                    ForEach(trendingShows, id: \.id) { s in
                        NavigationLink {
                            ShowInfoView(tmdb: s).modelContext(context)
                        } label: {
                            ShowResultRow(
                                title: s.title,
                                subtitle: s.year.map(String.init),
                                posterPath: s.posterPath
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func loadingOrEmptySection(trimmed: String) -> some View {
        if isLoading {
            ProgressView("Searching…")
        } else if let err = errorText {
            ContentUnavailableView(
                "Search failed",
                systemImage: "exclamationmark.triangle",
                description: Text(err)
            )
        } else if !trimmed.isEmpty && currentResultsIsEmpty {
            Text("No results").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func movieResultsSection() -> some View {
        ForEach(movieResults, id: \.tmdb.id) { hit in
            NavigationLink {
                MovieInfoView(tmdb: hit.tmdb)
                    .modelContext(context)
            } label: {
                MovieResultRow(
                    title: hit.tmdb.title,
                    subtitle: hit.tmdb.year.map(String.init),
                    posterPath: hit.tmdb.posterPath,
                    predicted: hasEnoughHistory() ? hit.predicted : nil
                )
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                let inList = isInWatchlist(tmdbId: hit.tmdb.id)
                Button {
                    toggleWatchlist(for: hit.tmdb)
                } label: {
                    Label(inList ? "Remove" : "Watchlist", systemImage: inList ? "bookmark.slash" : "bookmark")
                }
                .tint(inList ? .red : .blue)
            }
        }
    }

    @ViewBuilder
    private func showResultsSection() -> some View {
        ForEach(showResults, id: \.id) { s in
            NavigationLink {
                ShowInfoView(tmdb: s)
                    .modelContext(context)
            } label: {
                ShowResultRow(
                    title: s.title,
                    subtitle: s.year.map(String.init),
                    posterPath: s.posterPath
                )
            }
        }
    }

    // MARK: - Helpers

    @MainActor
    private func refreshWatchlistCache() {
        // Fetch all user items and cache TMDb IDs that are in the watchlist state
        let items: [UserItem] = (try? context.fetch(FetchDescriptor<UserItem>())) ?? []
        watchlistTMDbIDs = Set(items
            .filter { $0.state == .watchlist }
            .compactMap { $0.movie?.tmdbID }
        )
    }

    private var currentResultsIsEmpty: Bool {
        switch domain {
        case .movies: return movieResults.isEmpty
        case .shows:  return showResults.isEmpty
        }
    }

    // Debounced entry point
    @MainActor
    private func scheduleSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        errorText = nil
        guard !trimmed.isEmpty else {
            movieResults = []
            showResults = []
            return
        }
        await debouncer.schedule(after: 0.30) {
            await runSearch(trimmed)
        }
    }

    @MainActor
    private func runGenreQuickFilter(_ genreID: Int) async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let page = try await TMDbClient.shared.discoverMovies(genreIDs: [genreID])
            // Train taste model and compute predictions
            tasteModel.train(from: context)
            movieResults = page.results.map { tm in
                let pred = tasteModel.predict(for: ghostMovie(from: tm))
                return MovieHit(tmdb: tm, predicted: pred)
            }
            // Record the filter as a recent search label (optional)
            if let name = quickFilterGenres.first(where: { $0.id == genreID })?.name {
                recentStore.add(name)
            }
        } catch {
            movieResults = []
            errorText = error.localizedDescription
        }
    }

    // Execute the search and (for movies) compute predictions
    @MainActor
    private func runSearch(_ q: String) async {
        isLoading = true
        defer { isLoading = false }

        let client = TMDbClient.shared

        do {
            switch domain {
            case .movies:
                let movies = try await client.search(query: q)
                // Train (or refresh) taste model once per result set
                tasteModel.train(from: context)
                // Map results into hits with predictions
                movieResults = movies.map { tm in
                    let pred = tasteModel.predict(for: ghostMovie(from: tm))
                    return MovieHit(tmdb: tm, predicted: pred)
                }

            case .shows:
                let shows = try await client.searchShows(query: q)
                showResults = shows
            }
            recentStore.add(q)
            errorText = nil
        } catch {
            // Fail-soft: clear only the active list
            if domain == .movies {
                movieResults = []
            } else {
                showResults = []
            }
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func loadPopularIfNeeded() async {
        guard popular.isEmpty, !isLoadingPopular else { return }
        isLoadingPopular = true
        defer { isLoadingPopular = false }
        do {
            let page = try await TMDbClient.shared.popularMovies(page: 1)
            popular = Array(page.results.prefix(12))
            computeTopPicks()
            errorText = nil
        } catch {
            // Fail-soft: don't overwrite existing errorText for main search; just keep popular empty
        }
    }

    @MainActor
    private func loadTrendingShowsIfNeeded() async {
        guard trendingShows.isEmpty, !isLoadingTrendingShows else { return }
        isLoadingTrendingShows = true
        defer { isLoadingTrendingShows = false }
        do {
            let page = try await TMDbClient.shared.popularShows(page: 1)
            trendingShows = Array(page.results.prefix(12))
        } catch {
            trendingShows = []
        }
    }

    @MainActor
    private func computeTopPicks() {
        guard !popular.isEmpty else { topPicks = []; return }
        // Use taste model predictions if possible; otherwise return a subset
        let scored = popular.map { tm in
            // Build a ghost Movie to score
            let ghost = Movie(
                title: tm.title,
                year: tm.year,
                tmdbID: tm.id,
                posterPath: tm.posterPath,
                genreIDs: tm.genreIDs,
                ownerId: SessionManager.shared.userId ?? "guest"
            )
            return (tm, tasteModel.predict(for: ghost))
        }
        topPicks = scored.sorted { $0.1 > $1.1 }.prefix(10).map { $0.0 }
    }

    /// Build a lightweight, non-persisted Movie to feed into the TasteModel.
    private func ghostMovie(from tm: TMDbMovie) -> Movie {
        Movie(
            title: tm.title,
            year: tm.year,
            tmdbID: tm.id,
            posterPath: tm.posterPath,
            genreIDs: tm.genreIDs,
            ownerId: SessionManager.shared.userId ?? "guest"
        )
    }

    @MainActor
    private func hasEnoughHistory() -> Bool {
        let items: [UserItem] = (try? context.fetch(FetchDescriptor<UserItem>())) ?? []
        let seenCount = items.filter { $0.state == .seen }.count
        return seenCount >= 5
    }

    @MainActor
    private func isInWatchlist(tmdbId: Int) -> Bool {
        return watchlistTMDbIDs.contains(tmdbId)
    }

    @MainActor
    private func toggleWatchlist(for tm: TMDbMovie) {
        let tmdbIdOpt: Int? = tm.id
        // Try to find local movie by TMDb id
        var movieFD = FetchDescriptor<Movie>(predicate: #Predicate { $0.tmdbID == tmdbIdOpt })
        movieFD.fetchLimit = 1
        let owner = SessionManager.shared.userId ?? "guest"

        let movie: Movie
        if let fetched = try? context.fetch(movieFD), let m = fetched.first {
            movie = m
        } else {
            let m = Movie(
                title: tm.title,
                year: tm.year,
                tmdbID: tm.id,
                posterPath: tm.posterPath,
                genreIDs: tm.genreIDs,
                ownerId: owner
            )
            context.insert(m)
            movie = m
        }

        let movieIDOpt: UUID? = movie.id
        // Fetch items for this movie id and then check for a watchlist item in memory
        var itemFD = FetchDescriptor<UserItem>(predicate: #Predicate { $0.movie?.id == movieIDOpt })
        itemFD.fetchLimit = 5
        if let found = try? context.fetch(itemFD), let item = found.first(where: { $0.state == .watchlist }) {
            // Remove from watchlist by deleting the item (keep movie record)
            context.delete(item)
        } else {
            context.insert(UserItem(movie: movie, state: .watchlist, ownerId: owner))
        }

        SD.save(context)
        refreshWatchlistCache()
    }
}

// MARK: - Movie hit (result + prediction)

private struct MovieHit: Hashable {
    let tmdb: TMDbMovie
    let predicted: Double

    static func == (lhs: MovieHit, rhs: MovieHit) -> Bool {
        return lhs.tmdb.id == rhs.tmdb.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(tmdb.id)
    }
}

// MARK: - Rows (private to this file to avoid conflicts)

private struct MovieResultRow: View {
    let title: String
    let subtitle: String?
    let posterPath: String?
    let predicted: Double?

    var body: some View {
        HStack(spacing: 12) {
            PosterThumb(posterPath: posterPath, title: title, width: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let s = subtitle {
                    Text(s).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let value = predicted {
                PredictedRatingBadge(value: value)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ShowResultRow: View {
    let title: String
    let subtitle: String?
    let posterPath: String?

    var body: some View {
        HStack(spacing: 12) {
            PosterThumb(posterPath: posterPath, title: title, width: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let s = subtitle {
                    Text(s).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

