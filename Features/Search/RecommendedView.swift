import SwiftUI
import SwiftData

struct RecommendedView: View {
    @Environment(\.modelContext) private var context
    @State private var userId: String = "guest"
    
    @State private var recommendations: [TMDbItem] = []
    @State private var isLoading = false
    @State private var filter: String = "movie" // movie, tv, book, podcast
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $filter) {
                    Text("Movies").tag("movie")
                    Text("TV").tag("tv")
                    Text("Books").tag("book")
                    Text("Podcasts").tag("podcast")
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: filter) { _, _ in Task { await generateRecommendations() } }
                
                Group {
                    if isLoading {
                        ProgressView("Curating for you...")
                    } else if recommendations.isEmpty {
                        ContentUnavailableView("No Matches", systemImage: "star.slash", description: Text("Try rating more items to improve recommendations."))
                    } else {
                        List(recommendations, id: \.id) { m in
                            NavigationLink {
                                if filter == "book" { BookInfoView(item: m).modelContext(context) }
                                else if filter == "podcast" { PodcastInfoView(item: m).modelContext(context) }
                                else { MovieInfoView(tmdb: m, mediaType: filter).modelContext(context) }
                            } label: {
                                HStack(spacing: 16) {
                                    if let path = m.posterPath, path.contains("http") {
                                         AsyncImage(url: URL(string: path)) { p in if let i = p.image { i.resizable().scaledToFill() } else { Color.gray.opacity(0.1) } }.frame(width: 60, height: 90).cornerRadius(4)
                                    } else {
                                        PosterThumb(posterPath: m.posterPath, title: m.displayTitle, width: 60)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(m.displayTitle).font(.headline)
                                        HStack { Image(systemName: "sparkles").foregroundStyle(.purple); Text("For You").font(.caption).bold().foregroundStyle(.purple) }
                                            .padding(.vertical, 4).padding(.horizontal, 8).background(Color.purple.opacity(0.1), in: Capsule())
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("For You")
            .task {
                let actor = AuthService.shared.sessionActor()
                if let s = try? await actor.session() { userId = s.userId }
                await generateRecommendations()
            }
        }
    }
    
    private func generateRecommendations() async {
        isLoading = true
        do {
            var pool: [TMDbItem] = []
            
            // 1. Fetch Candidates based on type
            if filter == "movie" {
                let client = try TMDbClient()
                let pop = try await client.popularMovies(page: 1)
                let top = try await client.popularMovies(page: 2)
                pool = pop.results + top.results
            } else if filter == "tv" {
                let client = try TMDbClient()
                let pop = try await client.popularTV(page: 1)
                pool = pop.results
            } else if filter == "book" {
                // Mock trending books: Search for "bestseller" or generic topic
                pool = try await BooksAPI().searchBooks(query: "fiction bestseller")
            } else if filter == "podcast" {
                // Mock trending podcasts: Search for "podcast"
                pool = try await PodcastsAPI().search(query: "podcast")
            }
            
            // 2. Score Candidates
            let engine = LinearPredictionEngine()
            var highMatches: [TMDbItem] = []
            
            for item in pool {
                // Create temp object for scoring
                // Note: Use displayTitle/year for basic matching
                let temp = Movie(
                    title: item.displayTitle,
                    year: item.year,
                    tmdbID: item.id,
                    posterPath: item.posterPath,
                    genreIDs: item.genreIds ?? [],
                    tags: item.tags ?? [],
                    mediaType: filter,
                    ownerId: userId
                )
                
                let pred = engine.predict(for: temp, in: context, userId: userId)
                if pred.score >= 7.0 { highMatches.append(item) }
            }
            
            self.recommendations = highMatches.sorted { $0.year ?? 0 > $1.year ?? 0 } // Show newer stuff first
            
        } catch {
            print("Rec error: \(error)")
        }
        isLoading = false
    }
}
