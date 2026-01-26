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

    var body: some View {
        NavigationStack {
            List {
                // MARK: - SEARCH RESULTS
                if hasSearched && !query.isEmpty {
                    if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }.listRowSeparator(.hidden)
                    } else if results.isEmpty {
                        ContentUnavailableView.search(text: query)
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
                        Section(header: Text("🍿 In Theaters")) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(inTheaters, id: \.id) { m in DiscoveryCard(item: m) }
                                }.padding(.vertical, 8)
                            }.listRowInsets(EdgeInsets())
                        }
                    }
                    
                    if !streaming.isEmpty {
                        Section(header: Text("📺 Streaming Now")) {
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
        do {
            async let tmdbTask = TMDbClient().searchMulti(query: query)
            async let booksTask = BooksAPI().searchBooks(query: query)
            async let podcastsTask = PodcastsAPI().search(query: query)
            
            let (tmdbPage, bookResults, podcastResults) = try await (tmdbTask, booksTask, podcastsTask)
            let visualResults = tmdbPage.results.filter { $0.mediaType == "movie" || $0.mediaType == "tv" }
            
            self.results = visualResults + bookResults + podcastResults
            self.hasSearched = true
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
