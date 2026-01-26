import SwiftUI
import SwiftData

private typealias AppMovie = Movie

/// Landing page for a movie selected from search.
/// Shows poster, title/year, ratings (IMDb/RT/MC), overview, cast,
/// and where to watch. Actions: Mark as Watched, Want to Watch.
struct MovieInfoView: View {
    @Environment(\.modelContext) private var context

    let tmdb: TMDbMovie

    @State private var movie: AppMovie? = nil
    @State private var details: MovieDetails? = nil
    @State private var isLoading = false
    @State private var errorText: String? = nil
    @State private var imdbFromCache: String? = nil

    @State private var showMarkSheet = false
    @State private var showCompare = false
    @State private var showRankHint = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if isLoading {
                    ProgressView("Loading…")
                } else if let err = errorText {
                    ContentUnavailableView("Couldn’t load details",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(err))
                } else if let d = details {
                    ratingsRow(d)
                    if let ov = d.overview, !ov.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Overview").font(.headline)
                            Text(ov)
                        }
                    }
                    if d.runtimeMinutes ?? 0 > 0 || !d.genres.isEmpty {
                        HStack(spacing: 12) {
                            if let m = d.runtimeMinutes { InfoChip(text: "\(m) min") }
                            ForEach(d.genres.prefix(6), id: \.self) { g in InfoChip(text: g) }
                        }
                    }
                    if !d.cast.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Top Cast").font(.headline)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(d.cast) { c in
                                        VStack(spacing: 6) {
                                            if let url = TMDbClient.makeImageURL(path: c.profilePath, size: .w185) {
                                                AsyncImage(url: url) { phase in
                                                    switch phase {
                                                    case .empty:
                                                        Circle().fill(Color.secondary.opacity(0.15))
                                                            .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                                                    case .success(let img):
                                                        img.resizable()
                                                            .scaledToFill()
                                                            .frame(width: 48, height: 48)
                                                            .clipShape(Circle())
                                                    case .failure:
                                                        Circle().fill(Color.secondary.opacity(0.15))
                                                            .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                                                    @unknown default:
                                                        Circle().fill(Color.secondary.opacity(0.15))
                                                            .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                                                    }
                                                }
                                                .frame(width: 48, height: 48)
                                            } else {
                                                Circle().fill(Color.secondary.opacity(0.15))
                                                    .frame(width: 48, height: 48)
                                                    .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                                            }
                                            Text(c.name).font(.caption).lineLimit(1)
                                            if let ch = c.character, !ch.isEmpty {
                                                Text(ch).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                        }
                                        .frame(width: 96)
                                    }
                                }
                            }
                        }
                    }
                    if !(d.providersFlatrate.isEmpty && d.providersRent.isEmpty && d.providersBuy.isEmpty) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Where to Watch").font(.headline)
                            providerGroup("Included", d.providersFlatrate)
                            providerGroup("Rent", d.providersRent)
                            providerGroup("Buy", d.providersBuy)
                        }
                    }
                }

                Divider().padding(.vertical, 4)
                actionBar
            }
            .padding()
        }
        .navigationTitle(tmdb.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            if movie == nil { movie = ensureMovie(from: tmdb) }
            await loadDetails()
        }
        .sheet(isPresented: $showMarkSheet, onDismiss: {}) {
            if let movie {
                MarkWatchedSheet(movie: movie, onComplete: {
                    let items: [UserItem] = (try? context.fetch(FetchDescriptor<UserItem>())) ?? []
                    let seenCount = items.filter { $0.state == .seen }.count
                    if seenCount >= 2 {
                        showCompare = true
                    } else {
                        showRankHint = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            showRankHint = false
                        }
                    }
                })
                .modelContext(context)
            }
        }
        .sheet(isPresented: $showCompare, onDismiss: { showCompare = false }) {
            CompareView(seed: movie)
                .modelContext(context)
        }
        .overlay(alignment: .top) {
            if showRankHint {
                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                    Text("Add one more watched movie to start ranking")
                        .font(.subheadline).bold()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Poster(posterPath: tmdb.posterPath ?? movie?.posterPath, title: tmdb.title)
                .frame(width: 120)
            VStack(alignment: .leading, spacing: 6) {
                Text(tmdb.title).font(.title3).bold()
                if let date = tmdb.releaseDate, let y = date.prefix(4).toInt() { Text(String(y)).foregroundStyle(.secondary) }
            }
            Spacer()
        }
    }

    // MARK: - Ratings

    @ViewBuilder
    private func ratingsRow(_ d: MovieDetails) -> some View {
        if (d.imdbRating != nil || imdbFromCache != nil) || d.rottenTomatoes != nil || d.metacritic != nil {
            let imdbValue = d.imdbRating ?? imdbFromCache
            HStack(spacing: 12) {
                if let v = imdbValue { badge("IMDb", v) }
                if let v = d.rottenTomatoes { badge("Rotten Tomatoes", v) }
                if let v = d.metacritic { badge("Metacritic", v) }
            }
        }
    }

    private func badge(_ source: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(source).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).bold()
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func providerGroup(_ title: String, _ providers: [String]) -> some View {
        Group {
            if !providers.isEmpty {
                HStack(spacing: 8) {
                    Text(title).font(.subheadline).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(providers, id: \.self) { p in InfoChip(text: p) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                showMarkSheet = true
            } label: {
                Label("Mark as Watched", systemImage: "checkmark.circle")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)

            Button {
                saveToWatchlist()
            } label: {
                Label("Want to Watch", systemImage: "bookmark")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Data

    @MainActor
    private func loadDetails() async {
        guard !isLoading else { return }
        isLoading = true; errorText = nil
        defer { isLoading = false }
        do {
            details = try await MovieDetailsService.fetch(for: tmdb)
            // Fill in IMDb rating from cache if the details didn't include it
            if details?.imdbRating == nil {
                var fd = FetchDescriptor<ExternalRatingCache>(predicate: #Predicate { $0.tmdbID == tmdb.id })
                fd.fetchLimit = 1
                if let cached = try? context.fetch(fd).first, let imdb = cached.imdbRating {
                    imdbFromCache = String(format: "%.1f", imdb)
                }
            } else {
                imdbFromCache = nil
            }
        } catch {
            errorText = error.localizedDescription
            details = nil
        }
    }

    private func ensureMovie(from tm: TMDbMovie) -> AppMovie {
        // Try to find existing by TMDb id, else create
        let existing: [AppMovie] = (try? context.fetch(FetchDescriptor<AppMovie>())) ?? []
        if let m = existing.first(where: { $0.tmdbID == tm.id }) { return m }
        let owner = SessionManager.shared.userId ?? "guest"
        let m = AppMovie(
            title: tm.title,
            year: tm.releaseDate.flatMap { String($0.prefix(4)) }.flatMap { Int($0) },
            tmdbID: tm.id,
            posterPath: tm.posterPath,
            genreIDs: tm.genreIDs,
            ownerId: owner
        )
        context.insert(m)
        SD.save(context)
        return m
    }

    private func saveToWatchlist() {
        guard let movie else { return }
        _ = SessionManager.shared.userId
        let items: [UserItem] = (try? context.fetch(FetchDescriptor<UserItem>())) ?? []
        if items.first(where: { $0.movie?.id == movie.id && $0.state == UserItem.State.watchlist }) == nil {
            context.insert(
                UserItem(
                    movie: movie,
                    state: UserItem.State.watchlist,
                    ownerId: SessionManager.shared.userId ?? "guest"
                )
            )
            SD.save(context)
        }
    }
}

// MARK: - Small chips

private struct InfoChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption).bold()
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

private extension StringProtocol {
    func toInt() -> Int? { Int(self) }
}
