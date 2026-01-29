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

    @State private var isLoading = false
    @State private var hasSearched = false
    @State private var errorText: String? = nil
    @State private var didYouMeanSuggestion: String? = nil
    @State private var fuzzySuggestions: [String] = []

    // Get known titles from local library for suggestions
    @Query private var allMovies: [Movie]
    var localTitles: [String] {
        allMovies.map { $0.title }
    }

    var body: some View {
        NavigationStack {
            List {
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
            // FIX: Mac doesn't support .grouped, so we handle it here
            #if os(iOS)
            .listStyle(.grouped)
            #else
            .listStyle(.inset)
            #endif
            
            .navigationTitle(query.isEmpty ? "Explore" : "Search")
            .searchable(text: $query, prompt: "Movies, TV, Books, Podcasts...")
            .task(id: query) {
                if query.isEmpty { hasSearched = false; return }
                hasSearched = false
                try? await Task.sleep(nanoseconds: 600_000_000)
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

        do {
            async let tmdbTask = TMDbClient().searchMulti(query: query)
            async let booksTask = BooksAPI().searchBooks(query: query)
            async let podcastsTask = PodcastsAPI().search(query: query)

            let (tmdbPage, bookResults, podcastResults) = try await (tmdbTask, booksTask, podcastsTask)
            let visualResults = tmdbPage.results.filter { $0.mediaType == "movie" || $0.mediaType == "tv" }

            self.results = visualResults + bookResults + podcastResults
            self.hasSearched = true

            // Generate fuzzy suggestions if no results
            if results.isEmpty && query.count >= 2 {
                // Combine local titles with popular titles for suggestions
                let allKnownTitles = Array(Set(localTitles + FuzzySearch.popularTitles))

                // Find "Did you mean?" suggestion
                if let suggestion = FuzzySearch.didYouMean(query: query, knownTitles: allKnownTitles) {
                    didYouMeanSuggestion = suggestion
                }

                // Find similar titles
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
    
    private func loadDiscovery() async {
        do {
            let client = try TMDbClient()
            async let trendTask = client.getTrending()
            async let theaterTask = client.getNowPlaying()
            async let streamTask = client.getStreaming()
            let (trend, theater, stream) = try await (trendTask, theaterTask, streamTask)
            self.trending = trend.results; self.inTheaters = theater.results; self.streaming = stream.results
        } catch { print("Discovery Error: \(error)") }
    }
    
    // Subviews
    func SearchResultRow(item: TMDbItem) -> some View {
        NavigationLink { destination(for: item) } label: {
            HStack(spacing: 12) {
                if let path = item.posterPath, path.contains("http") {
                    AsyncImage(url: URL(string: path)) { p in if let i = p.image { i.resizable().scaledToFill() } else { Color.gray.opacity(0.2) } }.frame(width: 48, height: 72).cornerRadius(4)
                } else { PosterThumb(posterPath: item.posterPath, title: item.displayTitle, width: 48) }
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
        else { MovieInfoView(tmdb: item, mediaType: item.mediaType ?? "movie").modelContext(context) }
    }
    
    func Badge(type: String) -> some View {
        var color: Color = .orange; var label = "Movie"
        if type == "tv" { color = .blue; label = "TV" }
        else if type == "book" { color = .green; label = "Book" }
        else if type == "podcast" { color = .purple; label = "Podcast" }
        return Text(label).font(.caption2).fontWeight(.bold).padding(.horizontal, 6).padding(.vertical, 2).background(color.opacity(0.1)).foregroundColor(color).cornerRadius(4)
    }
}

// MARK: - Fuzzy Search
struct FuzzySearch {

    /// Calculate the Levenshtein distance between two strings
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
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }

        return matrix[m][n]
    }

    /// Calculate similarity score between two strings (0.0 to 1.0)
    static func similarity(_ s1: String, _ s2: String) -> Double {
        let distance = levenshteinDistance(s1, s2)
        let maxLen = max(s1.count, s2.count)
        if maxLen == 0 { return 1.0 }
        return 1.0 - (Double(distance) / Double(maxLen))
    }

    /// Check if query is a fuzzy match for title (allows for typos)
    static func isFuzzyMatch(query: String, title: String, threshold: Double = 0.7) -> Bool {
        let query = query.lowercased()
        let title = title.lowercased()

        // Exact substring match
        if title.contains(query) { return true }

        // Check if query matches start of title
        let titlePrefix = String(title.prefix(query.count + 2))
        if similarity(query, titlePrefix) >= threshold { return true }

        // Check word-by-word matching
        let titleWords = title.split(separator: " ").map(String.init)
        for word in titleWords {
            if similarity(query, word) >= threshold { return true }
        }

        // Full similarity check for short queries
        if query.count <= 10 && similarity(query, title) >= threshold * 0.8 {
            return true
        }

        return false
    }

    /// Find suggestions from a list of titles based on fuzzy matching
    static func findSuggestions(
        query: String,
        in titles: [String],
        maxResults: Int = 5,
        minSimilarity: Double = 0.5
    ) -> [String] {
        guard !query.isEmpty else { return [] }

        let scored = titles.map { title -> (String, Double) in
            let sim = similarity(query, title)
            // Boost score if title starts with query
            let boost = title.lowercased().hasPrefix(query.lowercased()) ? 0.3 : 0.0
            return (title, min(sim + boost, 1.0))
        }

        return scored
            .filter { $0.1 >= minSimilarity }
            .sorted { $0.1 > $1.1 }
            .prefix(maxResults)
            .map { $0.0 }
    }

    /// Generate "Did you mean?" suggestions based on common movie titles
    static func didYouMean(query: String, knownTitles: [String]) -> String? {
        guard query.count >= 3 else { return nil }

        var bestMatch: (title: String, score: Double)? = nil

        for title in knownTitles {
            let score = similarity(query, title)
            // Only suggest if it's close but not exact
            if score >= 0.6 && score < 1.0 {
                if bestMatch == nil || score > bestMatch!.score {
                    bestMatch = (title, score)
                }
            }
        }

        return bestMatch?.title
    }

    /// Popular movie titles for quick suggestions
    static let popularTitles: [String] = [
        "The Shawshank Redemption",
        "The Godfather",
        "The Dark Knight",
        "Pulp Fiction",
        "Forrest Gump",
        "Inception",
        "The Matrix",
        "Interstellar",
        "Fight Club",
        "Goodfellas",
        "The Avengers",
        "Spider-Man",
        "Batman",
        "Superman",
        "Star Wars",
        "Harry Potter",
        "Lord of the Rings",
        "Jurassic Park",
        "Titanic",
        "Avatar",
        "The Lion King",
        "Toy Story",
        "Finding Nemo",
        "Frozen",
        "Despicable Me",
        "Minions",
        "Shrek",
        "Inside Out",
        "Coco",
        "Moana",
        "Encanto",
        "Oppenheimer",
        "Barbie",
        "John Wick",
        "Top Gun",
        "Mission Impossible",
        "Fast and Furious",
        "Transformers",
        "Pirates of the Caribbean"
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
                        MovieInfoView(tmdb: movie, mediaType: "movie")
                            .modelContext(context)
                    } label: {
                        HStack(spacing: 12) {
                            PosterThumb(posterPath: movie.posterPath, title: movie.displayTitle, width: 60)
                                .cornerRadius(8)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(movie.displayTitle)
                                    .font(.headline)
                                    .lineLimit(2)
                                if let year = movie.year {
                                    Text(String(year))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("In Theaters")
        .task {
            await loadMovies()
        }
    }

    private func loadMovies() async {
        do {
            let client = try TMDbClient()
            let response = try await client.getNowPlaying()
            self.movies = response.results
        } catch {
            print("Failed to load in theaters: \(error)")
        }
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
                        MovieInfoView(tmdb: movie, mediaType: "movie")
                            .modelContext(context)
                    } label: {
                        HStack(spacing: 12) {
                            PosterThumb(posterPath: movie.posterPath, title: movie.displayTitle, width: 60)
                                .cornerRadius(8)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(movie.displayTitle)
                                    .font(.headline)
                                    .lineLimit(2)
                                if let year = movie.year {
                                    Text(String(year))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Streaming Now")
        .task {
            await loadMovies()
        }
    }

    private func loadMovies() async {
        do {
            let client = try TMDbClient()
            let response = try await client.getStreaming()
            self.movies = response.results
        } catch {
            print("Failed to load streaming: \(error)")
        }
        isLoading = false
    }
}
