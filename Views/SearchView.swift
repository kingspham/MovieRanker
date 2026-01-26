import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

// Keep the segmented control to switch between Search and For You
private enum SearchMode: String, CaseIterable, Identifiable {
    case search = "Search"
    case forYou = "For You"
    var id: String { rawValue }
}

// New scope control for the Search page
enum SearchScope: String, CaseIterable { case all = "All", library = "Library", tmdb = "Online" }

struct SearchView: View {
    @State private var mode: SearchMode = .search
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    ForEach(SearchMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                Divider()

                switch mode {
                case .search:
                    UnifiedSearchPage(navigateTo: { movie in
                        path.append(movie.id)
                    })
                    .navigationDestination(for: UUID.self) { id in
                        MovieDetailsHostByID(id: id)
                    }
                case .forYou:
                    ForYouPage()
                }
            }
            .navigationTitle("Search")
        }
    }
}

// MARK: - Search (replaced with user's unified search UI + kept recent integrations)

private struct UnifiedSearchPage: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var recents = RecentSearchStore.shared

    var navigateTo: (Movie) -> Void

    @State private var scope: SearchScope = .all
    @State private var query: String = ""
    @State private var results: [UnifiedSearchResult] = []
    @State private var isLoading = false
    @State private var errorText: String?
    private let debounce = Debouncer()

    // Sheet/notifications integration preserved
    @State private var justSavedTitle: String? = nil
    @State private var compareAnchorID: UUID? = nil
    @State private var detailsAnchorID: UUID? = nil

    #if os(iOS)
    @State private var haptic = UIImpactFeedbackGenerator(style: .light)
    #endif

    var body: some View {
        VStack(spacing: 0) {
            // Search bar + scope
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Search movies…", text: $query, onCommit: submitSearch)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    #endif
                    #if os(iOS)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                        }
                    }
                    #endif
                    if !query.isEmpty {
                        Button {
                            query = ""
                            results = []
                        } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.12)))

                Picker("Scope", selection: $scope) {
                    ForEach(SearchScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .padding([.horizontal, .top])

            if isLoading { ProgressView().padding() }

            if !query.isEmpty && results.isEmpty && !isLoading {
                VStack(spacing: 12) {
                    Image(systemName: "popcorn.fill").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("No results").foregroundStyle(.secondary)
                }
                .padding(.top, 24)
            }

            if query.isEmpty && !recents.recent.isEmpty {
                // Recent searches / chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recents.recent, id: \.self) { r in
                            Button {
                                query = r
                                Task { await performSearch() }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "clock")
                                    Text(r)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(Color.gray.opacity(0.12)))
                            }
                        }
                        if !recents.recent.isEmpty {
                            Button(role: .destructive) { recents.clear() } label: {
                                Label("Clear", systemImage: "trash")
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }

            List {
                ForEach(filtered(results)) { r in
                    SearchResultRow(result: r) {
                        // Primary tap: if local, open detail; if remote, add then open
                        if let m = r.local {
                            navigateTo(m)
                        } else {
                            SearchService.shared.addToLibraryFromTMDb(result: r, context: modelContext, ownerId: SessionManager.shared.userId)
                            if let created = fetchMovieBy(title: r.title, year: r.year) {
                                navigateTo(created)
                            }
                        }
                    } onQuickAdd: {
                        #if os(iOS)
                        haptic.impactOccurred()
                        #endif
                        if r.isInLibrary, let m = r.local {
                            SearchService.shared.toggleWatchState(movie: m, context: modelContext)
                        } else {
                            SearchService.shared.addToLibraryFromTMDb(result: r, context: modelContext, ownerId: SessionManager.shared.userId)
                        }
                        // refresh result row state quickly
                        Task { await performSearch(skipRecents: true) }
                    }
                }
            }
            .listStyle(.plain)
        }
        .onReceive(NotificationCenter.default.publisher(for: .movieDidSave)) { note in
            if let title = note.object as? String {
                withAnimation { justSavedTitle = title }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation { justSavedTitle = nil }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .presentCompareForMovie)) { note in
            if let id = note.object as? UUID { compareAnchorID = id }
        }
        .onReceive(NotificationCenter.default.publisher(for: .presentMovieDetails)) { note in
            if let id = note.object as? UUID {
                // Prefer push if router is available via navigateTo; otherwise fallback to sheet
                detailsAnchorID = id
            }
        }
        .overlay(alignment: .top) {
            if let msg = justSavedTitle {
                ToastBanner(text: "Saved \(msg)!")
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(item: Binding<IDBox?>(
            get: { compareAnchorID.map { IDBox(id: $0) } },
            set: { compareAnchorID = $0?.id }
        )) { box in
            CompareView(anchorID: box.id)
        }
        .sheet(item: Binding<IDBox?>(
            get: { detailsAnchorID.map { IDBox(id: $0) } },
            set: { detailsAnchorID = $0?.id }
        )) { box in
            MovieDetailsHostByID(id: box.id)
        }
        .onChange(of: query) { _, _ in
            Task { await debounce.schedule(after: 0.25) { await performSearch() } }
        }
        .onChange(of: scope) { _, _ in
            Task { await performSearch(skipRecents: true) }
        }
    }

    private func filtered(_ list: [UnifiedSearchResult]) -> [UnifiedSearchResult] {
        switch scope {
        case .all: return list
        case .library: return list.filter { $0.isInLibrary }
        case .tmdb: return list.filter { !$0.isInLibrary }
        }
    }

    private func submitSearch() {
        Task { await performSearch() }
    }

    private func performSearch(skipRecents: Bool = false) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { self.results = []; return }
        isLoading = true; defer { isLoading = false }
        let out = await SearchService.shared.run(query: q, context: modelContext)
        // Exact match boost: pin exact (case-insensitive) title matches to the top
        let loweredQ = q.lowercased()
        let boosted = out.sorted { a, b in
            let aExact = a.title.lowercased() == loweredQ
            let bExact = b.title.lowercased() == loweredQ
            if aExact != bExact { return aExact && !bExact }
            return false
        }
        self.results = boosted
        if !skipRecents { recents.add(q) }
    }

    private func fetchMovieBy(title: String, year: Int?) -> Movie? {
        // Prefer normalized titleLower if available in your model
        let movies: [Movie] = (try? modelContext.fetch(FetchDescriptor<Movie>())) ?? []
        let lowered = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Try titleLower + year match first if property exists, else fall back to title compare
        if let match = movies.first(where: { ($0.titleLower == lowered) && ($0.year == year) }) { return match }
        if let match = movies.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame && $0.year == year }) { return match }
        return movies.first { $0.title.caseInsensitiveCompare(title) == .orderedSame }
    }
}

// MARK: - For You (kept from existing file)

private struct ForYouPage: View {
    @Query private var allMovies: [Movie]
    @Query private var allScores: [Score]

    @State private var candidates: [TMDbMovie] = []
    @State private var recs: [(TMDbMovie, Int)] = []  // (movie, predictedScore)
    @State private var isLoading = false
    @State private var selected: TMDbMovie? = nil
    @State private var showDetails = false
    @State private var justSavedTitle: String? = nil

    var body: some View {
        List {
            if recs.isEmpty && isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if recs.isEmpty {
                Text("No recommendations yet. Rate a few movies first!")
                    .foregroundStyle(.secondary)
            } else {
                Section("Recommended for you") {
                    ForEach(recs, id: \.0.id) { pair in
                        let m = pair.0
                        let p = pair.1
                        Button {
                            selected = m
                            showDetails = true
                        } label: {
                            HStack(spacing: 12) {
                                PosterThumb(path: m.posterPath, width: 44, height: 66)
                                    .frame(width: 44, height: 66)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.title).font(.headline)
                                    if let y = m.year {
                                        Text("\(y)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Text("\(p)")
                                    .font(.subheadline).bold()
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().stroke(.secondary))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
#if os(iOS)
        .listStyle(.insetGrouped)
#else
        .listStyle(.inset)
#endif
        .onAppear { Task { await loadRecommendations() } }
        .sheet(isPresented: $showDetails) {
            if let s = selected {
                LogMovieDetailsView(
                    pendingTitle: s.title,
                    pendingYear: s.year,
                    pendingTMDbID: s.id,
                    pendingPosterPath: s.posterPath,
                    pendingGenreIDs: s.genreIDs,
                    pendingPopularity: s.popularity,
                    onFinish: { _ in
                        withAnimation { justSavedTitle = s.title }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation { justSavedTitle = nil }
                        }
                    }
                )
            }
        }
        .overlay(alignment: .top) {
            if let msg = justSavedTitle {
                ToastBanner(text: "Saved \(msg)!")
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func loadRecommendations() async {
        guard let api = TMDbClient() else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            // Candidate set = popular movies
            candidates = try await api.popular(page: 1)

            // Build user taste vector from your seen movies with scores
            let seenWithScores: [(genreIDs: [Int], score100: Double)] = allScores.compactMap { s in
                guard
                    let m = allMovies.first(where: { $0.id == s.movieID }),
                    let gids = m.genreIDs,
                    !gids.isEmpty
                else { return nil }
                return (gids, s.display100)
            }

            let weights = Recommender.userGenreWeights(seen: seenWithScores)

            // Filter out movies you already have (by tmdbID when possible, else title+year)
            let existingKeys: Set<String> = Set(allMovies.map { keyFor(movie: $0) })

            let unseen = candidates.filter { m in
                let k = keyFor(tmdb: m)
                return !existingKeys.contains(k)
            }

            // Predict & sort
            let scored: [(TMDbMovie, Int)] = unseen.map { m in
                let p = Recommender.predictScore100(genreIDs: m.genreIDs, weights: weights)
                return (m, p)
            }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 } // higher predicted first
                // tie-breaker by popularity desc
                return (a.0.popularity ?? 0) > (b.0.popularity ?? 0)
            }

            self.recs = Array(scored.prefix(20))
        } catch {
            self.recs = []
        }
    }

    private func keyFor(movie: Movie) -> String {
        if let id = movie.tmdbID { return "tmdb:\(id)" }
        return "\(movie.title.lowercased())|\(movie.year ?? -1)"
    }
    private func keyFor(tmdb: TMDbMovie) -> String {
        "tmdb:\(tmdb.id)"
    }
}

// Host detail views by id for notification-driven navigation
private struct MovieDetailsHostByID: View, Identifiable {
    @Environment(\.modelContext) private var context
    let id: UUID
    var identity: UUID { id }
    var body: some View {
        // Fetch the movie by id; if missing, show a placeholder
        let movies = (try? context.fetch(FetchDescriptor<Movie>())) ?? []
        if let m = movies.first(where: { $0.id == id }) {
            MovieDetailView(movie: m)
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading…").foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

private struct IDBox: Identifiable { let id: UUID }
