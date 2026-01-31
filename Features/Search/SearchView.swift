// SearchView.swift
import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var context
    @State private var userId: String = "guest"

    @State private var query: String = ""
    @State private var results: [TMDbItem] = []

    // Discovery Data
    @State private var trending: [TMDbItem] = []
    @State private var inTheaters: [TMDbItem] = []
    @State private var streaming: [TMDbItem] = []
    @State private var suggestedMovies: [TMDbItem] = []
    @State private var suggestedShows: [TMDbItem] = []

    // Query user's scores for personalized suggestions
    @Query private var allScores: [Score]

    @State private var isLoading = false
    @State private var hasSearched = false
    @State private var errorText: String? = nil
    @State private var didYouMeanSuggestion: String? = nil
    @State private var fuzzySuggestions: [String] = []

    // Recent searches for autocomplete
    @StateObject private var recentSearchStore = RecentSearchStore()

    // Track if search field is focused
    @State private var isSearchFocused = false

    // Cached autocomplete suggestions (computed async to avoid UI lag)
    @State private var cachedAutocompleteSuggestions: [String] = []

    // Get known titles from local library for suggestions (cached to avoid repeated fetches)
    @Query private var allMovies: [Movie]
    private var localTitles: [String] { allMovies.map(\.title) }

    // Simplified autocomplete - fast, no expensive fuzzy matching during typing
    private func updateAutocompleteSuggestions() {
        guard query.count >= 2, !hasSearched else {
            cachedAutocompleteSuggestions = []
            return
        }

        let queryLower = query.lowercased()
        var suggestions: [String] = []

        // 1. Check recent searches that match (fast - simple contains)
        let recentMatches = recentSearchStore.recent.filter {
            $0.lowercased().contains(queryLower)
        }
        suggestions.append(contentsOf: recentMatches.prefix(3))

        // 2. Check local library titles that match (fast - simple prefix/contains)
        let localMatches = allMovies.lazy
            .map { $0.title }
            .filter { $0.lowercased().hasPrefix(queryLower) || $0.lowercased().contains(queryLower) }
            .prefix(4)
        for match in localMatches {
            if !suggestions.contains(where: { $0.lowercased() == match.lowercased() }) {
                suggestions.append(match)
            }
        }

        // 3. Check popular titles (fast - simple contains, skip fuzzy during typing)
        let popularMatches = FuzzySearch.popularTitles.filter {
            $0.lowercased().contains(queryLower)
        }.prefix(3)
        for match in popularMatches {
            if !suggestions.contains(where: { $0.lowercased() == match.lowercased() }) {
                suggestions.append(match)
            }
        }

        cachedAutocompleteSuggestions = Array(suggestions.prefix(6))
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - AUTOCOMPLETE SUGGESTIONS (shown while typing, before search completes)
                if !query.isEmpty && !hasSearched && !cachedAutocompleteSuggestions.isEmpty {
                    Section {
                        ForEach(cachedAutocompleteSuggestions, id: \.self) { suggestion in
                            Button {
                                query = suggestion
                            } label: {
                                HStack {
                                    Image(systemName: recentSearchStore.recent.contains(where: { $0.lowercased() == suggestion.lowercased() }) ? "clock.arrow.circlepath" : "magnifyingglass")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(suggestion)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "arrow.up.left")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Suggestions")
                    }
                }

                // MARK: - RECENT SEARCHES (only shown when search is focused AND query is empty)
                if isSearchFocused && query.isEmpty && !recentSearchStore.recent.isEmpty {
                    Section {
                        ForEach(recentSearchStore.recent.prefix(5), id: \.self) { search in
                            Button {
                                query = search
                            } label: {
                                HStack {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(search)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Button(role: .destructive) {
                            recentSearchStore.clear()
                        } label: {
                            Text("Clear Recent Searches")
                                .font(.subheadline)
                        }
                    } header: {
                        Text("Recent Searches")
                    }
                }

                // MARK: - SEARCH RESULTS
                if hasSearched && !query.isEmpty {
                    if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }.listRowSeparator(.hidden)
                    } else if results.isEmpty {
                        // Show fuzzy suggestions when no results
                        VStack(spacing: 16) {
                            ContentUnavailableView.search(text: query)

                            if let suggestion = didYouMeanSuggestion {
                                VStack(spacing: 8) {
                                    Text("Did you mean:")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Button {
                                        query = suggestion
                                    } label: {
                                        Text(suggestion)
                                            .font(.headline)
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(12)
                            }

                            if !fuzzySuggestions.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Try searching for:")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    ForEach(fuzzySuggestions, id: \.self) { suggestion in
                                        Button {
                                            query = suggestion
                                        } label: {
                                            HStack {
                                                Image(systemName: "magnifyingglass")
                                                    .font(.caption)
                                                Text(suggestion)
                                                    .font(.body)
                                            }
                                            .foregroundStyle(.blue)
                                        }
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(results, id: \.id) { item in
                            SearchResultRow(item: item)
                        }
                    }
                }
                // MARK: - DISCOVERY
                else {
                    // Suggested Movies (high predicted score movies)
                    if !suggestedMovies.isEmpty {
                        Section(header: HStack {
                            Text("🎬 Suggested Movies")
                            Spacer()
                            NavigationLink("See All") {
                                SuggestedMediaView(userId: userId, mediaType: "movie")
                            }
                            .font(.caption)
                        }) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(suggestedMovies, id: \.id) { m in DiscoveryCard(item: m) }
                                }.padding(.vertical, 8)
                            }.listRowInsets(EdgeInsets())
                        }
                    }

                    // Suggested Shows (high predicted score TV shows)
                    if !suggestedShows.isEmpty {
                        Section(header: HStack {
                            Text("📺 Suggested Shows")
                            Spacer()
                            NavigationLink("See All") {
                                SuggestedMediaView(userId: userId, mediaType: "tv")
                            }
                            .font(.caption)
                        }) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(suggestedShows, id: \.id) { m in DiscoveryCard(item: m) }
                                }.padding(.vertical, 8)
                            }.listRowInsets(EdgeInsets())
                        }
                    }

                    if !trending.isEmpty {
                        Section(header: Text("🔥 Trending Today")) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(trending, id: \.id) { m in DiscoveryCard(item: m) }
                                }.padding(.vertical, 8)
                            }.listRowInsets(EdgeInsets())
                        }
                    }

                    if !inTheaters.isEmpty {
                        Section(header: HStack {
                            Text("🍿 In Theaters")
                            Spacer()
                            NavigationLink("See All") {
                                InTheatersView()
                            }
                            .font(.caption)
                        }) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(inTheaters, id: \.id) { m in DiscoveryCard(item: m) }
                                }.padding(.vertical, 8)
                            }.listRowInsets(EdgeInsets())
                        }
                    }

                    if !streaming.isEmpty {
                        Section(header: HStack {
                            Text("📺 Streaming Now")
                            Spacer()
                            NavigationLink("See All") {
                                StreamingNowView()
                            }
                            .font(.caption)
                        }) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(streaming, id: \.id) { m in DiscoveryCard(item: m) }
                                }.padding(.vertical, 8)
                            }.listRowInsets(EdgeInsets())
                        }
                    }
                }
            }
            #if os(iOS)
            .listStyle(.grouped)
            #else
            .listStyle(.inset)
            #endif

            .navigationTitle(query.isEmpty ? "Explore" : "Search")
            .searchable(text: $query, isPresented: $isSearchFocused, prompt: "Movies, TV, People, Books, Podcasts...")
            .onChange(of: query) { _, newValue in
                updateAutocompleteSuggestions()
            }
            .task(id: query) {
                if query.isEmpty { hasSearched = false; cachedAutocompleteSuggestions = []; return }
                hasSearched = false
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                await performUnifiedSearch()
            }
            .task { await loadDiscovery() }
        }
    }

    private func performUnifiedSearch() async {
        isLoading = true
        didYouMeanSuggestion = nil
        fuzzySuggestions = []

        let searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !searchQuery.isEmpty {
            recentSearchStore.add(searchQuery)
        }

        guard searchQuery.count >= 2 else {
            results = []
            hasSearched = false
            isLoading = false
            return
        }

        do {
            async let tmdbTask = TMDbClient().searchMulti(query: query)
            async let booksTask = BooksAPI().searchBooks(query: query)
            async let podcastsTask = PodcastsAPI().search(query: query)

            let (tmdbPage, bookResults, podcastResults) = try await (tmdbTask, booksTask, podcastsTask)

            // Include movie, tv, AND person results
            let visualResults = tmdbPage.results.filter {
                $0.mediaType == "movie" || $0.mediaType == "tv" || $0.mediaType == "person"
            }

            // Reorder results: prioritize persons when query looks like a name
            let reorderedResults = reorderSearchResults(visualResults, query: searchQuery)

            self.results = reorderedResults + bookResults + podcastResults
            self.hasSearched = true

            if results.isEmpty && query.count >= 2 {
                let allKnownTitles = Array(Set(localTitles + FuzzySearch.popularTitles))
                if let suggestion = FuzzySearch.didYouMean(query: query, knownTitles: allKnownTitles) {
                    didYouMeanSuggestion = suggestion
                }
                fuzzySuggestions = FuzzySearch.findSuggestions(
                    query: query,
                    in: allKnownTitles,
                    maxResults: 4,
                    minSimilarity: 0.4
                ).filter { $0 != didYouMeanSuggestion }
            }
        } catch { print("Search Error: \(error)") }
        isLoading = false
    }

    private func reorderSearchResults(_ results: [TMDbItem], query: String) -> [TMDbItem] {
        let queryLower = query.lowercased()
        let titleKeywords = ["the ", "movie", "show", "series", "season", "part", "episode", "vol", "2", "3", "ii", "iii"]
        let looksLikeTitle = titleKeywords.contains { queryLower.contains($0) }

        if looksLikeTitle { return results }

        let words = query.split(separator: " ")
        let looksLikeName = words.count >= 2 && words.count <= 4 && !query.contains(where: { $0.isNumber })

        if looksLikeName {
            let persons = results.filter { $0.mediaType == "person" }.sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
            let others = results.filter { $0.mediaType != "person" }
            return persons + others
        }

        return results
    }

    private func loadDiscovery() async {
        do {
            let client = try TMDbClient()
            async let trendTask = client.getTrending()
            async let theaterTask = client.getNowPlaying()
            async let streamTask = client.getStreaming()
            let (trend, theater, stream) = try await (trendTask, theaterTask, streamTask)
            self.trending = trend.results
            self.inTheaters = theater.results
            self.streaming = stream.results
            await loadSuggestedForYou(client: client)
        } catch { print("Discovery Error: \(error)") }
    }

    private func loadSuggestedForYou(client: TMDbClient) async {
        let userScores = allScores.filter { ($0.ownerId == userId || $0.ownerId == "guest") && $0.display100 >= 70 }

        var genreCount: [Int: Int] = [:]
        var seenTmdbIds = Set<Int>()

        for score in userScores {
            if let movie = allMovies.first(where: { $0.id == score.movieID }) {
                if let tmdbId = movie.tmdbID { seenTmdbIds.insert(tmdbId) }
                for genreId in movie.genreIDs ?? [] {
                    genreCount[genreId, default: 0] += 1
                }
            }
        }

        let topGenres = genreCount.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
        guard !topGenres.isEmpty else { return }

        let movieGenreToTVGenre: [Int: Int] = [
            28: 10759, 12: 10759, 878: 10765, 14: 10765
        ]

        do {
            async let movieTask = client.discoverByGenres(genreIds: Array(topGenres))
            async let tvTask = client.discoverTVByGenres(genreIds: Array(topGenres.map { movieGenreToTVGenre[$0] ?? $0 }))
            let (movieResponse, tvResponse) = try await (movieTask, tvTask)
            let movieSuggestions = movieResponse.results.filter { !seenTmdbIds.contains($0.id) }
            let tvSuggestions = tvResponse.results.filter { !seenTmdbIds.contains($0.id) }
            self.suggestedMovies = Array(movieSuggestions.prefix(10))
            self.suggestedShows = Array(tvSuggestions.prefix(10))
        } catch {
            print("Suggestions Error: \(error)")
        }
    }

    // Subviews
    func SearchResultRow(item: TMDbItem) -> some View {
        NavigationLink { destination(for: item) } label: {
            HStack(spacing: 12) {
                // Handle person results differently (circular profile image)
                if item.mediaType == "person" {
                    if let profilePath = item.profilePath,
                       let url = TMDbClient.makeImageURL(path: profilePath, size: .w185) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFill()
                            } else {
                                Circle().fill(Color.gray.opacity(0.2))
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .foregroundStyle(.gray)
                                    )
                            }
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                    } else {
                        Circle().fill(Color.gray.opacity(0.2))
                            .frame(width: 48, height: 48)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.gray)
                            )
                    }
                } else if let path = item.posterPath, path.contains("http") {
                    AsyncImage(url: URL(string: path)) { p in if let i = p.image { i.resizable().scaledToFill() } else { Color.gray.opacity(0.2) } }.frame(width: 48, height: 72).cornerRadius(4)
                } else {
                    PosterThumb(posterPath: item.posterPath, title: item.displayTitle, width: 48)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle).font(.headline)
                    HStack(spacing: 6) { Badge(type: item.mediaType ?? "movie"); if let y = item.year { Text(String(y)).font(.caption).foregroundStyle(.secondary) } }
                }
            }
        }
    }

    func DiscoveryCard(item: TMDbItem) -> some View {
        NavigationLink { destination(for: item) } label: {
            VStack(alignment: .leading) {
                PosterThumb(posterPath: item.posterPath, title: item.displayTitle, width: 100).shadow(radius: 4)
                Text(item.displayTitle).font(.caption).bold().lineLimit(1).frame(width: 100).foregroundStyle(.primary)
            }
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private func destination(for item: TMDbItem) -> some View {
        if item.mediaType == "book" { BookInfoView(item: item).modelContext(context) }
        else if item.mediaType == "podcast" { PodcastInfoView(item: item).modelContext(context) }
        else if item.mediaType == "person" { PersonDetailView(personId: item.id, personName: item.displayTitle) }
        else { MovieInfoView(tmdb: item, mediaType: item.mediaType ?? "movie").modelContext(context) }
    }

    func Badge(type: String) -> some View {
        var color: Color = .orange; var label = "Movie"
        if type == "tv" { color = .blue; label = "TV" }
        else if type == "book" { color = .green; label = "Book" }
        else if type == "podcast" { color = .purple; label = "Podcast" }
        else if type == "person" { color = .pink; label = "Actor" }
        return Text(label).font(.caption2).fontWeight(.bold).padding(.horizontal, 6).padding(.vertical, 2).background(color.opacity(0.1)).foregroundColor(color).cornerRadius(4)
    }
}

// MARK: - Fuzzy Search
struct FuzzySearch {

    static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1.lowercased())
        let s2 = Array(s2.lowercased())
        let m = s1.count
        let n = s2.count
        if m == 0 { return n }
        if n == 0 { return m }
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                let cost = s1[i - 1] == s2[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }
        return matrix[m][n]
    }

    static func similarity(_ s1: String, _ s2: String) -> Double {
        let distance = levenshteinDistance(s1, s2)
        let maxLen = max(s1.count, s2.count)
        if maxLen == 0 { return 1.0 }
        return 1.0 - (Double(distance) / Double(maxLen))
    }

    static func isFuzzyMatch(query: String, title: String, threshold: Double = 0.7) -> Bool {
        let query = query.lowercased()
        let title = title.lowercased()
        if title.contains(query) { return true }
        let titlePrefix = String(title.prefix(query.count + 2))
        if similarity(query, titlePrefix) >= threshold { return true }
        let titleWords = title.split(separator: " ").map(String.init)
        for word in titleWords {
            if similarity(query, word) >= threshold { return true }
        }
        if query.count <= 10 && similarity(query, title) >= threshold * 0.8 { return true }
        return false
    }

    static func findSuggestions(query: String, in titles: [String], maxResults: Int = 5, minSimilarity: Double = 0.5) -> [String] {
        guard !query.isEmpty else { return [] }
        let scored = titles.map { title -> (String, Double) in
            let sim = similarity(query, title)
            let boost = title.lowercased().hasPrefix(query.lowercased()) ? 0.3 : 0.0
            return (title, min(sim + boost, 1.0))
        }
        return scored.filter { $0.1 >= minSimilarity }.sorted { $0.1 > $1.1 }.prefix(maxResults).map { $0.0 }
    }

    static func didYouMean(query: String, knownTitles: [String]) -> String? {
        guard query.count >= 3 else { return nil }
        var bestMatch: (title: String, score: Double)? = nil
        for title in knownTitles {
            let score = similarity(query, title)
            if score >= 0.6 && score < 1.0 {
                if bestMatch == nil || score > bestMatch!.score {
                    bestMatch = (title, score)
                }
            }
        }
        return bestMatch?.title
    }

    static let popularTitles: [String] = [
        "The Shawshank Redemption", "The Godfather", "The Dark Knight", "Pulp Fiction",
        "Forrest Gump", "Inception", "The Matrix", "Interstellar", "Fight Club", "Goodfellas",
        "The Avengers", "Spider-Man", "Batman", "Superman", "Star Wars", "Harry Potter",
        "Lord of the Rings", "Jurassic Park", "Titanic", "Avatar", "The Lion King", "Toy Story",
        "Finding Nemo", "Frozen", "Despicable Me", "Minions", "Shrek", "Inside Out", "Coco",
        "Moana", "Encanto", "Oppenheimer", "Barbie", "John Wick", "Top Gun", "Mission Impossible",
        "Fast and Furious", "Transformers", "Pirates of the Caribbean"
    ]
}

// MARK: - In Theaters View
struct InTheatersView: View {
    @Environment(\.modelContext) private var context
    @State private var movies: [TMDbItem] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if movies.isEmpty {
                ContentUnavailableView("No Movies Found", systemImage: "film", description: Text("Couldn't load movies currently in theaters"))
            } else {
                List(movies, id: \.id) { movie in
                    NavigationLink {
                        MovieInfoView(tmdb: movie, mediaType: "movie").modelContext(context)
                    } label: {
                        HStack(spacing: 12) {
                            PosterThumb(posterPath: movie.posterPath, title: movie.displayTitle, width: 60).cornerRadius(8)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(movie.displayTitle).font(.headline).lineLimit(2)
                                if let year = movie.year { Text(String(year)).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("In Theaters")
        .task { await loadMovies() }
    }

    private func loadMovies() async {
        do {
            let client = try TMDbClient()
            let response = try await client.getNowPlaying()
            self.movies = response.results
        } catch { print("Failed to load in theaters: \(error)") }
        isLoading = false
    }
}

// MARK: - Streaming Now View
struct StreamingNowView: View {
    @Environment(\.modelContext) private var context
    @State private var movies: [TMDbItem] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if movies.isEmpty {
                ContentUnavailableView("No Movies Found", systemImage: "play.tv", description: Text("Couldn't load streaming movies"))
            } else {
                List(movies, id: \.id) { movie in
                    NavigationLink {
                        MovieInfoView(tmdb: movie, mediaType: "movie").modelContext(context)
                    } label: {
                        HStack(spacing: 12) {
                            PosterThumb(posterPath: movie.posterPath, title: movie.displayTitle, width: 60).cornerRadius(8)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(movie.displayTitle).font(.headline).lineLimit(2)
                                if let year = movie.year { Text(String(year)).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Streaming Now")
        .task { await loadMovies() }
    }

    private func loadMovies() async {
        do {
            let client = try TMDbClient()
            let response = try await client.getStreaming()
            self.movies = response.results
        } catch { print("Failed to load streaming: \(error)") }
        isLoading = false
    }
}

// MARK: - Suggested For You View
struct SuggestedForYouView: View {
    @Environment(\.modelContext) private var context
    let userId: String

    @Query private var allMovies: [Movie]
    @Query private var allScores: [Score]

    @State private var suggestions: [TMDbItem] = []
    @State private var isLoading = true
    @State private var topGenreNames: [String] = []

    private let genreIdToName: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy",
        80: "Crime", 99: "Documentary", 18: "Drama", 10751: "Family",
        14: "Fantasy", 36: "History", 27: "Horror", 10402: "Music",
        9648: "Mystery", 10749: "Romance", 878: "Sci-Fi", 10770: "TV Movie",
        53: "Thriller", 10752: "War", 37: "Western"
    ]

    private let movieGenreToTVGenre: [Int: Int] = [
        28: 10759, 12: 10759, 878: 10765, 14: 10765
    ]

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Analyzing your taste...").font(.subheadline).foregroundStyle(.secondary)
                }
            } else if suggestions.isEmpty {
                ContentUnavailableView("No Suggestions Yet", systemImage: "star.fill", description: Text("Rate more movies to get personalized recommendations!"))
            } else {
                List {
                    if !topGenreNames.isEmpty {
                        Section {
                            Text("Based on your love of \(topGenreNames.joined(separator: ", "))").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(suggestions, id: \.id) { movie in
                        NavigationLink {
                            MovieInfoView(tmdb: movie, mediaType: movie.mediaType ?? "movie").modelContext(context)
                        } label: {
                            HStack(spacing: 12) {
                                PosterThumb(posterPath: movie.posterPath, title: movie.displayTitle, width: 60).cornerRadius(8)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(movie.displayTitle).font(.headline).lineLimit(2)
                                    HStack(spacing: 6) {
                                        if movie.mediaType == "tv" {
                                            Text("TV").font(.caption2).fontWeight(.bold).padding(.horizontal, 6).padding(.vertical, 2).background(Color.blue.opacity(0.1)).foregroundColor(.blue).cornerRadius(4)
                                        }
                                        if let year = movie.year { Text(String(year)).font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Suggested For You")
        .task { await loadSuggestions() }
    }

    private func loadSuggestions() async {
        let userScores = allScores.filter { ($0.ownerId == userId || $0.ownerId == "guest") && $0.display100 >= 70 }
        var genreCount: [Int: Int] = [:]
        var seenTmdbIds = Set<Int>()

        for score in userScores {
            if let movie = allMovies.first(where: { $0.id == score.movieID }) {
                if let tmdbId = movie.tmdbID { seenTmdbIds.insert(tmdbId) }
                for genreId in movie.genreIDs ?? [] { genreCount[genreId, default: 0] += 1 }
            }
        }

        let topGenres = genreCount.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
        topGenreNames = topGenres.compactMap { genreIdToName[$0] }

        guard !topGenres.isEmpty else { isLoading = false; return }

        do {
            let client = try TMDbClient()
            async let movieTask = client.discoverByGenres(genreIds: Array(topGenres))
            async let tvTask = client.discoverTVByGenres(genreIds: Array(topGenres.map { movieGenreToTVGenre[$0] ?? $0 }))
            let (movieResp, tvResp) = try await (movieTask, tvTask)
            var combined: [TMDbItem] = movieResp.results + tvResp.results
            combined = combined.filter { !seenTmdbIds.contains($0.id) }
            combined.sort { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
            self.suggestions = Array(combined.prefix(30))
        } catch { print("Failed to load suggestions: \(error)") }
        isLoading = false
    }
}

// MARK: - Suggested Media View (Movies or Shows)
struct SuggestedMediaView: View {
    @Environment(\.modelContext) private var context
    let userId: String
    let mediaType: String // "movie" or "tv"

    @Query private var allMovies: [Movie]
    @Query private var allScores: [Score]

    @State private var suggestions: [TMDbItem] = []
    @State private var isLoading = true
    @State private var topGenreNames: [String] = []

    private let genreIdToName: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy",
        80: "Crime", 99: "Documentary", 18: "Drama", 10751: "Family",
        14: "Fantasy", 36: "History", 27: "Horror", 10402: "Music",
        9648: "Mystery", 10749: "Romance", 878: "Sci-Fi", 10770: "TV Movie",
        53: "Thriller", 10752: "War", 37: "Western"
    ]

    private let movieGenreToTVGenre: [Int: Int] = [
        28: 10759, 12: 10759, 878: 10765, 14: 10765
    ]

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Finding \(mediaType == "movie" ? "movies" : "shows") for you...").font(.subheadline).foregroundStyle(.secondary)
                }
            } else if suggestions.isEmpty {
                ContentUnavailableView("No Suggestions Yet", systemImage: mediaType == "movie" ? "film" : "tv", description: Text("Rate more \(mediaType == "movie" ? "movies" : "shows") to get personalized recommendations!"))
            } else {
                List {
                    if !topGenreNames.isEmpty {
                        Section {
                            Text("Based on your love of \(topGenreNames.joined(separator: ", "))").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(suggestions, id: \.id) { item in
                        NavigationLink {
                            MovieInfoView(tmdb: item, mediaType: item.mediaType ?? mediaType).modelContext(context)
                        } label: {
                            HStack(spacing: 12) {
                                PosterThumb(posterPath: item.posterPath, title: item.displayTitle, width: 60).cornerRadius(8)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.displayTitle).font(.headline).lineLimit(2)
                                    if let year = item.year { Text(String(year)).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(mediaType == "movie" ? "Suggested Movies" : "Suggested Shows")
        .task { await loadSuggestions() }
    }

    private func loadSuggestions() async {
        let userScores = allScores.filter { ($0.ownerId == userId || $0.ownerId == "guest") && $0.display100 >= 70 }
        var genreCount: [Int: Int] = [:]
        var seenTmdbIds = Set<Int>()

        for score in userScores {
            if let movie = allMovies.first(where: { $0.id == score.movieID }) {
                if let tmdbId = movie.tmdbID { seenTmdbIds.insert(tmdbId) }
                for genreId in movie.genreIDs ?? [] { genreCount[genreId, default: 0] += 1 }
            }
        }

        let topGenres = genreCount.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
        topGenreNames = topGenres.compactMap { genreIdToName[$0] }

        guard !topGenres.isEmpty else { isLoading = false; return }

        do {
            let client = try TMDbClient()
            let results: [TMDbItem]
            if mediaType == "movie" {
                let response = try await client.discoverByGenres(genreIds: Array(topGenres))
                results = response.results
            } else {
                let tvGenres = topGenres.map { movieGenreToTVGenre[$0] ?? $0 }
                let response = try await client.discoverTVByGenres(genreIds: Array(tvGenres))
                results = response.results
            }
            var filtered = results.filter { !seenTmdbIds.contains($0.id) }
            filtered.sort { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
            self.suggestions = Array(filtered.prefix(30))
        } catch { print("Failed to load suggestions: \(error)") }
        isLoading = false
    }
}
