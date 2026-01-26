import SwiftUI
import SwiftData

/// Landing page for a show selected from search.
/// Shows poster, name/year, overview, cast, where-to-watch, and series ratings (best-effort).
/// Actions: Mark as Watched (opens MarkWatchedShowSheet), Want to Watch.
struct ShowInfoView: View {
    @Environment(\.modelContext) private var context

    let tmdb: TMDbShow   // you already have TMDbShow from your search client

    @State private var showModel: Show? = nil
    @State private var details: RichShowDetails? = nil
    @State private var isLoading = false
    @State private var errorText: String? = nil

    @State private var showMarkSheet = false

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

                    // Genres + counts
                    if d.seasons ?? 0 > 0 || d.episodes ?? 0 > 0 || !d.genres.isEmpty {
                        HStack(spacing: 12) {
                            if let s = d.seasons { InfoChip(text: "\(s) seasons") }
                            if let e = d.episodes { InfoChip(text: "\(e) episodes") }
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
                                            Circle().fill(Color.secondary.opacity(0.15))
                                                .frame(width: 48, height: 48)
                                                .overlay(
                                                    Image(systemName: "person.fill")
                                                        .foregroundStyle(.secondary)
                                                )
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
            if showModel == nil { showModel = ensureShow(from: tmdb) }
            await loadDetails()
        }
        .sheet(isPresented: $showMarkSheet, onDismiss: {}) {
            if let s = showModel {
                MarkWatchedShowSheet(show: s) { }
                    .modelContext(context)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            PosterThumb(posterPath: tmdb.posterPath, title: tmdb.title, width: 90)
            VStack(alignment: .leading, spacing: 6) {
                Text(tmdb.title).font(.title3).bold()
                if let y = tmdb.year { Text(String(y)).foregroundStyle(.secondary) }
            }
            Spacer()
        }
    }

    // MARK: - Ratings

    @ViewBuilder
    private func ratingsRow(_ d: RichShowDetails) -> some View {
        if d.imdbRating != nil || d.rottenTomatoes != nil || d.metacritic != nil {
            HStack(spacing: 12) {
                if let v = d.imdbRating { badge("IMDb", v) }
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
            details = try await ShowDetailsService.fetch(
                showID: tmdb.id,
                titleForFallback: tmdb.title,
                yearForFallback: tmdb.year
            )
        } catch {
            errorText = error.localizedDescription
            details = nil
        }
    }

    private func ensureShow(from tm: TMDbShow) -> Show {
        let existing: [Show] = (try? context.fetch(FetchDescriptor<Show>())) ?? []
        if let s = existing.first(where: { $0.tmdbID == tm.id }) { return s }
        let owner = SessionManager.shared.userId ?? "guest"
        let s = Show(
            title: tm.title,
            yearStart: tm.year,
            tmdbID: tm.id,
            posterPath: tm.posterPath,
            genreIDs: tm.genreIDs,
            popularity: tm.popularity,
            ownerId: owner
        )
        context.insert(s)
        SD.save(context)
        return s
    }

    private func saveToWatchlist() {
        guard let s = showModel else { return }
        let owner = SessionManager.shared.userId ?? "guest"
        let items: [UserItem] = (try? context.fetch(FetchDescriptor<UserItem>())) ?? []
        if items.first(where: { $0.show?.id == s.id }) == nil {
            context.insert(UserItem(movie: nil, show: s, state: .watchlist, ownerId: owner))
            SD.save(context)
        }
    }
}

// Small chip
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
