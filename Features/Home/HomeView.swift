import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context

    @State private var suggested: [TMDbItem] = []
    @State private var nowPlaying: [TMDbItem] = []
    @State private var upcoming:   [TMDbItem] = []
    @State private var loading = false
    @State private var errorText: String? = nil
    @State private var client: TMDbClient? = nil
    @State private var userId: String = "guest"

    var body: some View {
        NavigationStack {
            Group {
                if loading && nowPlaying.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Curating your feed...").foregroundStyle(.secondary)
                    }
                } else if let err = errorText {
                    ContentUnavailableView("Connection Failed", systemImage: "wifi.slash", description: Text(err))
                } else {
                    List {
                        // SUGGESTED
                        if !suggested.isEmpty {
                            Section(header: Text("✨ Picked for You")) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(suggested.prefix(8), id: \.id) { m in
                                            NavigationLink {
                                                MovieInfoView(tmdb: m, mediaType: "movie").modelContext(context)
                                            } label: {
                                                VStack(alignment: .leading) {
                                                    PosterThumb(posterPath: m.posterPath, title: m.displayTitle, width: 100)
                                                        .shadow(radius: 4)
                                                    Text(m.displayTitle)
                                                        .font(.caption).bold()
                                                        .lineLimit(1)
                                                        .frame(width: 100)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                                .listRowInsets(EdgeInsets())
                            }
                        }

                        // NOW PLAYING
                        if !nowPlaying.isEmpty {
                            Section(header: Text("🍿 In Theaters Now")) {
                                ForEach(nowPlaying, id: \.id) { m in
                                    NavigationLink {
                                        MovieInfoView(tmdb: m, mediaType: "movie").modelContext(context)
                                    } label: {
                                        MovieRow(movie: m, rightBadge: "In Theaters")
                                    }
                                }
                            }
                        }

                        // UPCOMING
                        if !upcoming.isEmpty {
                            Section(header: Text("🗓 Coming Soon")) {
                                ForEach(upcoming, id: \.id) { m in
                                    NavigationLink {
                                        MovieInfoView(tmdb: m, mediaType: "movie").modelContext(context)
                                    } label: {
                                        MovieRow(movie: m)
                                    }
                                }
                            }
                        }
                    }
                    #if os(iOS)
                    .listStyle(.grouped)
                    #else
                    .listStyle(.inset)
                    #endif
                }
            }
            .navigationTitle("Home")
            // NEW: Profile Button in Top Right
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(destination: ProfileView()) {
                        Image(systemName: "person.crop.circle")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .task {
                let actor = AuthService.shared.sessionActor()
                if let s = try? await actor.session() { userId = s.userId }
                do { client = try TMDbClient() }
                catch { errorText = error.localizedDescription }
                await refresh()
            }
        }
    }

    private func refresh() async {
        guard let client else { return }
        loading = true
        errorText = nil
        
        do {
            async let popularTask = client.popularMovies(page: 1)
            async let upcomingTask = client.searchMovies(query: "2025")
            
            let (popPage, upPage) = try await (popularTask, upcomingTask)
            
            self.nowPlaying = Array(popPage.results.prefix(8))
            self.upcoming = Array(upPage.results.prefix(8))
            
            // Suggestion Logic
            let suggestionPool = popPage.results
            var scoredMovies: [(movie: TMDbItem, score: Double)] = []
            let engine = LinearPredictionEngine()
            
            for tmdbMov in suggestionPool {
                let tempMovie = Movie(
                    title: tmdbMov.displayTitle,
                    year: tmdbMov.year,
                    tmdbID: tmdbMov.id,
                    posterPath: tmdbMov.posterPath,
                    genreIDs: tmdbMov.genreIds ?? [],
                    ownerId: userId
                )
                let prediction = engine.predict(for: tempMovie, in: context, userId: userId)
                scoredMovies.append((tmdbMov, prediction.score))
            }
            
            scoredMovies.sort { $0.score > $1.score }
            self.suggested = scoredMovies.map { $0.movie }
            
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }
}

private struct MovieRow: View {
    let movie: TMDbItem
    var rightBadge: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            PosterThumb(posterPath: movie.posterPath, title: movie.displayTitle, width: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(movie.displayTitle).font(.headline)
                if let y = movie.year {
                    Text(String(y)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let b = rightBadge {
                Text(b).font(.caption2).bold().padding(6).background(Color.gray.opacity(0.1), in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}
