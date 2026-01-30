// MovieInfoView.swift
// COMPLETE FILE - Full cloud sync + prediction tags

import SwiftUI
import SwiftData
import SafariServices

#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

struct MovieInfoView: View {
    @Environment(\.modelContext) private var context
    let tmdb: TMDbItem
    var mediaType: String = "movie"

    @State private var details: ShowDetails?
    @State private var cast: [CastMember] = []
    @State private var crew: [CrewMember] = []
    @State private var providers: [ProviderItem] = []
    @State private var prediction: PredictionExplanation?
    @State private var movie: Movie? = nil
    @State private var tvSeasons: [TMDbTVDetail.TMDbSeason] = []

    @State private var externalRatings: ExternalRatings?
    @State private var myLog: LogEntry?
    @State private var myScore: Score?
    @State private var isInWatchlist = false

    @State private var showSuccessMessage = false
    @State private var successMessageText = "Saved"
    @State private var userId: String = "guest"

    // Loading states for smooth UX
    @State private var isLoadingUserData = true
    @State private var isLoadingDetails = true
    
    enum ActiveSheet: Identifiable, Equatable {
        case browser(URL)
        case share(PlatformImage)
        case log(Movie, LogEntry?)
        case ranking(Movie)
        case showtimes(String) // Movie title for showtimes lookup
        var id: String {
            switch self {
            case .browser: return "browser"
            case .share: return "share"
            case .log: return "log"
            case .ranking: return "ranking"
            case .showtimes: return "showtimes"
            }
        }
        static func == (lhs: ActiveSheet, rhs: ActiveSheet) -> Bool {
            return lhs.id == rhs.id
        }
    }
    @State private var activeSheet: ActiveSheet?
    
    @State private var showCreateListAlert = false
    @State private var newListName = ""
    @Query private var myLists: [CustomList]
    
    var myScoreValue: Int? { myScore?.display100 }
    var hasRanked: Bool { myScoreValue != nil }
    
    var isInTheaters: Bool {
        guard let y = tmdb.year, mediaType == "movie" else { return false }
        let currentYear = Calendar.current.component(.year, from: Date())
        return y >= currentYear - 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HeroHeaderView(tmdb: tmdb, movie: movie, myLog: myLog, externalRatings: externalRatings)

                // Show loading indicator while user data loads, then show content
                if isLoadingUserData {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                } else {
                    ScoreOrPredictionView(myScoreValue: myScoreValue, prediction: prediction, removeRating: removeRating)
                }

                ActionsRowView(
                    hasRanked: hasRanked,
                    isInWatchlist: isInWatchlist,
                    myLists: myLists,
                    userId: userId,
                    onReRank: handleReRank,
                    onMarkWatched: { if let m = movie { activeSheet = .log(m, myLog) } },
                    onSaveToWatchlist: { Task { await saveToWatchlist() } },
                    onAddToList: { list in Task { await addToList(list) } },
                    onCreateList: { showCreateListAlert = true }
                )
                
                Divider().padding(.horizontal)
                
                SeasonsSectionView(mediaType: mediaType, tmdb: tmdb, tvSeasons: tvSeasons, context: context)
                if mediaType == "tv" && !tvSeasons.isEmpty {
                    Divider().padding(.horizontal)
                }
                
                ProvidersSectionView(providers: providers, title: tmdb.displayTitle)

                // Find Movie Times button for movies in theaters
                if isInTheaters {
                    Button {
                        activeSheet = .showtimes(tmdb.displayTitle)
                    } label: {
                        HStack {
                            Image(systemName: "ticket.fill")
                                .font(.title2)
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Find Movie Times")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("Now playing in theaters")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }

                if let ov = tmdb.overview, !ov.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Overview").font(.headline)
                        Text(ov).font(.body).foregroundStyle(.secondary).lineSpacing(4)
                    }
                    .padding(.horizontal)
                }
                
                TopCastSectionView(cast: cast)
                
                Spacer(minLength: 50)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if hasRanked {
                    Button { generateShareImage() } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        
        .sheet(item: $activeSheet) { item in
            switch item {
            case .browser(let url):
                #if os(iOS)
                SafariView(url: url).ignoresSafeArea()
                #else
                Text("Open \(url.absoluteString) in browser")
                #endif
            case .share(let img): ShareSheet(items: [img])
            case .log(let m, let existingLog):
                LogSheet(movie: m, existingLog: existingLog, showRanking: Binding(
                    get: { false },
                    set: { if $0 { activeSheet = .ranking(m) } }
                ))
            case .ranking(let m): RankingSheet(newMovie: m)
            case .showtimes(let title): ShowtimesSheet(movieTitle: title)
            }
        }
        .alert("Create List", isPresented: $showCreateListAlert) {
            TextField("List Name", text: $newListName)
            Button("Cancel", role: .cancel) { newListName = "" }
            Button("Create & Add") { Task { await createAndAddList() } }
        }
        .task {
            userId = AuthService.shared.currentUserId() ?? "guest"

            if movie == nil {
                movie = Movie.findOrCreate(from: tmdb, type: mediaType, context: context, ownerId: userId)
            }

            guard let m = movie else { return }

            // Load user data first (fast, local only) then clear loading state
            await loadUserData()
            isLoadingUserData = false

            // Calculate prediction in background to not block UI
            Task.detached(priority: .userInitiated) { @MainActor in
                let engine = LinearPredictionEngine()
                self.prediction = engine.predict(for: m, in: context, userId: userId)
            }

            if m.genreIDs.isEmpty { Task { await selfHealGenres(for: m) } }

            // Load network data in parallel (don't block UI)
            Task {
                async let ratingsTask: ExternalRatings? = {
                    do {
                        return try await ExternalRatingsService.fetch(forTitle: tmdb.displayTitle, year: tmdb.year)
                    } catch {
                        print("⚠️ Could not fetch external ratings: \(error)")
                        return nil
                    }
                }()
                async let detailsTask: Void = loadRichDetails()
                async let creditsTask: Void = loadCredits()
                async let providersTask: Void = loadProviders()
                async let enhancedDataTask: Void = loadEnhancedPredictionData()

                if mediaType == "tv" {
                    async let seasonsTask: Void = loadSeasons()
                    _ = await (detailsTask, creditsTask, providersTask, seasonsTask, enhancedDataTask)
                } else {
                    _ = await (detailsTask, creditsTask, providersTask, enhancedDataTask)
                }

                if let ratings = await ratingsTask {
                    await MainActor.run { self.externalRatings = ratings }
                }

                await MainActor.run { isLoadingDetails = false }
            }
        }
        .onChange(of: activeSheet) { _, newValue in
            if newValue == nil {
                Task { await loadUserData() }
            }
        }
        .overlay(alignment: .top) {
            if showSuccessMessage {
                SuccessToast(text: successMessageText)
            }
        }
    }
    
    // MARK: - Logic
    @MainActor private func generateShareImage() {
        guard let m = movie, let score = myScoreValue else { return }

        #if os(iOS)
        let renderer = ImageRenderer(content: FlexCardView(movieTitle: m.title, posterPath: m.posterPath, score: score, rank: nil, username: "Me", avatarInitial: "M"))
        renderer.scale = 3.0
        if let image = renderer.uiImage { activeSheet = .share(image) }
        #endif
    }

    private func openMovieTimes() {
        // Create a search URL for movie showtimes
        let movieTitle = tmdb.displayTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let searchQuery = "\(movieTitle) movie times near me"
        if let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
            #if os(iOS)
            UIApplication.shared.open(url)
            #endif
        }
    }

    private func loadSeasons() async {
        guard let client = try? TMDbClient() else { return }
        if let tvDetails = try? await client.getTVDetails(id: tmdb.id) {
            self.tvSeasons = (tvDetails.seasons ?? []).filter { $0.seasonNumber > 0 }
        }
    }
    
    private func loadRichDetails() async {
        let service = ShowDetailsService()
        if let d = try? await service.lookupByTitle(tmdb.displayTitle, year: tmdb.year) {
            withAnimation {
                self.details = d
                if let m = movie {
                    m.imdbRating = d.imdbRating
                    m.metaScore = d.metascore
                    m.rottenTomatoesRating = d.rottenTomatoes
                    try? context.save()
                }
            }
        }
    }

    /// Load enhanced TMDb data for better predictions (keywords, runtime, origin, etc.)
    private func loadEnhancedPredictionData() async {
        guard let client = try? TMDbClient(), let m = movie, let tmdbID = m.tmdbID else { return }

        do {
            if mediaType == "movie" {
                // Fetch full movie details and keywords in parallel
                let (details, keywords) = try await client.getFullMovieDetails(id: tmdbID)

                await MainActor.run {
                    // Populate enhanced prediction fields
                    m.runtime = details.runtime
                    m.budget = details.budget
                    m.voteAverage = details.voteAverage
                    m.voteCount = details.voteCount
                    m.originalLanguage = details.originalLanguage
                    m.productionCountries = details.productionCountries?.map { $0.iso31661 }
                    m.keywords = keywords

                    try? context.save()

                    // Re-calculate prediction with enhanced data
                    let engine = LinearPredictionEngine()
                    self.prediction = engine.predict(for: m, in: context, userId: userId)

                    print("✅ Loaded enhanced prediction data for \(m.title): \(keywords.count) keywords, runtime=\(details.runtime ?? 0)min, lang=\(details.originalLanguage ?? "?")")
                }
            } else if mediaType == "tv" {
                // Fetch full TV show details and keywords in parallel
                let (details, keywords) = try await client.getFullTVDetails(id: tmdbID)

                await MainActor.run {
                    // Populate enhanced prediction fields
                    m.runtime = details.episodeRunTime?.first // Average episode runtime
                    m.voteAverage = details.voteAverage
                    m.voteCount = details.voteCount
                    m.originalLanguage = details.originalLanguage
                    m.productionCountries = details.originCountry ?? details.productionCountries?.map { $0.iso31661 }
                    m.keywords = keywords

                    try? context.save()

                    // Re-calculate prediction with enhanced data
                    let engine = LinearPredictionEngine()
                    self.prediction = engine.predict(for: m, in: context, userId: userId)

                    print("✅ Loaded enhanced prediction data for TV \(m.title): \(keywords.count) keywords, lang=\(details.originalLanguage ?? "?")")
                }
            }
        } catch {
            print("⚠️ Could not fetch enhanced prediction data: \(error)")
        }
    }
    
    // 🆕 SAVES DIRECTOR/ACTOR TAGS FOR PREDICTIONS!
    private func loadCredits() async {
        guard let client = try? TMDbClient() else { return }
        
        if let creds = try? await client.getCredits(id: tmdb.id, type: mediaType) {
            withAnimation {
                self.cast = creds.cast
                self.crew = creds.crew
            }
            
            if let m = movie {
                var newTags: [String] = []
                
                // Add director(s)
                let directors = creds.crew.filter { $0.job == "Director" }
                for director in directors.prefix(2) {
                    let normalizedName = director.name
                        .lowercased()
                        .replacingOccurrences(of: " ", with: "_")
                        .replacingOccurrences(of: "'", with: "")
                        .replacingOccurrences(of: ".", with: "")
                    newTags.append("dir:\(normalizedName)")
                }
                
                // Add top cast (top 5 actors)
                for actor in creds.cast.prefix(5) {
                    let normalizedName = actor.name
                        .lowercased()
                        .replacingOccurrences(of: " ", with: "_")
                        .replacingOccurrences(of: "'", with: "")
                        .replacingOccurrences(of: ".", with: "")
                    newTags.append("actor:\(normalizedName)")
                }
                
                // Save tags to movie
                if !newTags.isEmpty {
                    m.tags = newTags
                    try? context.save()
                    
                    // Re-calculate prediction with new data
                    let engine = LinearPredictionEngine()
                    self.prediction = engine.predict(for: m, in: context, userId: userId)
                    
                    print("✅ Saved \(newTags.count) tags for \(m.title): \(newTags.joined(separator: ", "))")
                }
            }
        }
    }
    
    private func loadProviders() async {
        guard let client = try? TMDbClient() else { return }
        if let provs = try? await client.getWatchProviders(id: tmdb.id, type: mediaType) {
            withAnimation { self.providers = provs }
        }
    }
    
    @MainActor private func selfHealGenres(for m: Movie) async {
        guard let client = try? TMDbClient() else { return }
        if let details = try? await client.getDetails(id: m.tmdbID ?? 0, type: "movie"), let genres = details.genres {
            let ids = genres.map { $0.id }
            if !ids.isEmpty {
                m.genreIDs = ids
                try? context.save()
                let engine = LinearPredictionEngine()
                self.prediction = engine.predict(for: m, in: context, userId: userId)
            }
        }
    }
    
    // 🆕 FULL CLOUD SYNC ENABLED!
    @MainActor
    private func saveToWatchlist() async {
        guard let movie else { return }
        
        let targetID = movie.id
        let allItems = (try? context.fetch(FetchDescriptor<UserItem>())) ?? []
        let items = allItems.filter { $0.movie?.id == targetID }
        
            if !items.contains(where: { $0.state == .watchlist }) {
                let newItem = UserItem(movie: movie, state: .watchlist, ownerId: userId)
                context.insert(newItem)
                try? context.save()
                
                // 🆕 UPLOAD TO CLOUD!
                await SyncManager.shared.syncWatchlistAdd(movie: movie, item: newItem)
                
                isInWatchlist = true
                successMessageText = "Added to Watchlist"
                showSuccessMessage = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showSuccessMessage = false
                }
            }
    }
    
    // 🆕 FULL CLOUD SYNC ENABLED!
    @MainActor
    private func addToList(_ list: CustomList) async {
        guard let movie else { return }
        
        if !list.movieIDs.contains(movie.id) {
            list.movieIDs.append(movie.id)
            try? context.save()
            
            // 🆕 UPLOAD TO CLOUD!
            await SyncManager.shared.syncList(list: list)
            
            successMessageText = "Added to \(list.name)"
            showSuccessMessage = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showSuccessMessage = false
            }
        }
    }
    
    // 🆕 FULL CLOUD SYNC ENABLED!
    @MainActor
    private func createAndAddList() async {
        guard !newListName.isEmpty, let movie else { return }
        
        let newList = CustomList(name: newListName, ownerId: userId)
        newList.movieIDs.append(movie.id)
        context.insert(newList)
        try? context.save()
        
        // 🆕 UPLOAD TO CLOUD!
        await SyncManager.shared.syncList(list: newList)
        
        newListName = ""
        successMessageText = "Created list & added movie"
        showSuccessMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showSuccessMessage = false
        }
    }
    
    private func handleReRank() {
        guard let m = movie else { return }
        if let score = myScore {
            context.delete(score)
            try? context.save()
            Task { await ScoreService.shared.deleteScore(movieID: m.id) }
            myScore = nil
        }
        activeSheet = .ranking(m)
    }
    
    @MainActor
    private func removeRating() {
        guard let m = movie, let score = myScore else { return }
        context.delete(score)
        try? context.save()
        myScore = nil
        Task { await ScoreService.shared.deleteScore(movieID: m.id) }
        successMessageText = "Rating removed"
        showSuccessMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showSuccessMessage = false
        }
    }
    
    @MainActor
    private func loadUserData() async {
        guard let m = movie else { return }
        let movieID = m.id

        // Fetch and filter in memory (predicates have issues with captured variables and optional chaining)
        let allLogs = (try? context.fetch(FetchDescriptor<LogEntry>())) ?? []
        myLog = allLogs.first { $0.movie?.id == movieID && $0.ownerId == userId }

        let allScores = (try? context.fetch(FetchDescriptor<Score>())) ?? []
        myScore = allScores.first { $0.movieID == movieID && $0.ownerId == userId }

        let allItems = (try? context.fetch(FetchDescriptor<UserItem>())) ?? []
        let watchlistItems = allItems.filter { $0.movie?.id == movieID && $0.state == .watchlist && $0.ownerId == userId }
        isInWatchlist = !watchlistItems.isEmpty
    }
}

private struct HeroHeaderView: View {
    let tmdb: TMDbItem
    let movie: Movie?
    let myLog: LogEntry?
    let externalRatings: ExternalRatings?
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            PosterThumb(posterPath: tmdb.posterPath, title: tmdb.displayTitle, width: 120)
                .shadow(radius: 8)
            VStack(alignment: .leading, spacing: 6) {
                Text(tmdb.displayTitle)
                    .font(.title3)
                    .fontWeight(.black)
                if let genres = movie?.genreIDs, !genres.isEmpty {
                    Text(genres.map(genreIDToString).prefix(3).joined(separator: " • "))
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.secondary)
                }
                if let y = tmdb.year {
                    Text(tmdb.mediaType == "tv" ? "TV Series • \(y)" : String(y))
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                if let watchDate = myLog?.watchedOn {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Watched \(watchDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let ratings = externalRatings {
                    HStack(spacing: 12) {
                        if let imdb = ratings.imdb {
                            ExternalRatingBadge(source: "IMDb", score: imdb, color: .yellow)
                        }
                        if let rt = ratings.rottenTomatoes {
                            ExternalRatingBadge(source: "RT", score: rt, color: .red)
                        }
                        if let meta = ratings.metacritic {
                            ExternalRatingBadge(source: "Meta", score: meta, color: .green)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
    }
    
    private func genreIDToString(_ id: Int) -> String {
        switch id {
        case 28: return "Action"
        case 12: return "Adventure"
        case 16: return "Animation"
        case 35: return "Comedy"
        case 80: return "Crime"
        case 99: return "Documentary"
        case 18: return "Drama"
        case 10751: return "Family"
        case 14: return "Fantasy"
        case 36: return "History"
        case 27: return "Horror"
        case 10402: return "Music"
        case 9648: return "Mystery"
        case 10749: return "Romance"
        case 878: return "Sci-Fi"
        case 10770: return "TV Movie"
        case 53: return "Thriller"
        case 10752: return "War"
        case 37: return "Western"
        default: return "Genre"
        }
    }
}

private struct ScoreOrPredictionView: View {
    let myScoreValue: Int?
    let prediction: PredictionExplanation?
    let removeRating: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            if let score = myScoreValue {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(Color.blue, lineWidth: 4).frame(width: 50, height: 50)
                        Text("\(score)").font(.headline).fontWeight(.black).foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Score").font(.caption).textCase(.uppercase).foregroundStyle(.secondary)
                        Text("Ranked on Leaderboard").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                Button(role: .destructive) { removeRating() } label: {
                    Text("Remove Rating")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal)
            } else if let pred = prediction {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(Color.purple, lineWidth: 4).frame(width: 50, height: 50)
                        Text("\(Int(pred.score * 10))").font(.headline).fontWeight(.black).foregroundStyle(.purple)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Predicted Score").font(.caption).textCase(.uppercase).foregroundStyle(.secondary)
                        if !pred.reasons.isEmpty {
                            Text(pred.reasons.first ?? "Based on your tastes").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct ActionsRowView: View {
    let hasRanked: Bool
    let isInWatchlist: Bool
    let myLists: [CustomList]
    let userId: String
    let onReRank: () -> Void
    let onMarkWatched: () -> Void
    let onSaveToWatchlist: () -> Void
    let onAddToList: (CustomList) -> Void
    let onCreateList: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            if hasRanked {
                Button { onReRank() } label: {
                    Text("Re-Rank")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            } else {
                Button { onMarkWatched() } label: {
                    Text("Mark as Watched")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            Button { onSaveToWatchlist() } label: {
                Text(isInWatchlist ? "Added to Watchlist" : "Want to Watch")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isInWatchlist ? Color.green.opacity(0.2) : Color.gray.opacity(0.15))
                    .foregroundColor(isInWatchlist ? .green : .primary)
                    .cornerRadius(12)
            }
            .disabled(isInWatchlist)
            Menu {
                Text("Add to List")
                ForEach(myLists.filter { $0.ownerId == userId }) { list in
                    Button { onAddToList(list) } label: { Label(list.name, systemImage: "list.bullet") }
                }
                Divider()
                Button { onCreateList() } label: { Label("Create New List", systemImage: "plus") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.15))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal)
    }
}

private struct SeasonsSectionView: View {
    let mediaType: String
    let tmdb: TMDbItem
    let tvSeasons: [TMDbTVDetail.TMDbSeason]
    let context: ModelContext
    
    var body: some View {
        if mediaType == "tv" && !tvSeasons.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Seasons").font(.headline).padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(tvSeasons) { season in
                            NavigationLink {
                                MovieInfoView(
                                    tmdb: TMDbItem(
                                        id: season.id,
                                        title: "\(tmdb.displayTitle): \(season.name)",
                                        overview: "Season \(season.seasonNumber)",
                                        releaseDate: season.airDate,
                                        posterPath: season.posterPath ?? tmdb.posterPath,
                                        genreIds: tmdb.genreIds,
                                        mediaType: "tv"
                                    ),
                                    mediaType: "tv"
                                )
                                .modelContext(context)
                            } label: {
                                VStack {
                                    PosterThumb(posterPath: season.posterPath ?? tmdb.posterPath, title: season.name, width: 100)
                                        .shadow(radius: 4)
                                    Text(season.name)
                                        .font(.caption)
                                        .bold()
                                        .foregroundStyle(.primary)
                                    Text("\(season.episodeCount ?? 0) eps")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct ProvidersSectionView: View {
    let providers: [ProviderItem]
    let title: String
    
    var body: some View {
        if !providers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Where to Watch").font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(providers) { prov in
                            Button {
                                DeepLinkManager.open(providerName: prov.providerName, title: title) { url in
                                    // This button only opens; parent view handles sheet presentation.
                                    #if os(iOS)
                                    UIApplication.shared.open(url)
                                    #endif
                                }
                            } label: {
                                if let logo = prov.logoPath, let url = TMDbClient.makeImageURL(path: logo, size: .w185) {
                                    AsyncImage(url: url) { phase in
                                        if let img = phase.image { img.resizable().scaledToFit() } else { Color.gray.opacity(0.2) }
                                    }
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct TopCastSectionView: View {
    let cast: [CastMember]
    
    var body: some View {
        if !cast.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top Cast").font(.headline).padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(cast.prefix(10)) { member in
                            NavigationLink { PersonDetailView(personId: member.id, personName: member.name) } label: {
                                VStack {
                                    AsyncImage(url: TMDbClient.makeImageURL(path: member.profilePath, size: .w185)) { phase in
                                        if let img = phase.image { img.resizable().scaledToFill() } else { Color.gray.opacity(0.3) }
                                    }
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                                    Text(member.name)
                                        .font(.caption)
                                        .bold()
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .frame(width: 80)
                                        .foregroundStyle(.primary)
                                    if let char = member.character {
                                        Text(char)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(1)
                                            .frame(width: 80)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct ExternalRatingBadge: View {
    let source: String
    let score: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(source)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(score)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Showtimes Sheet (Simplified - Uses Google Search)
#if os(iOS)
import CoreLocation
import Combine

struct ShowtimesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let movieTitle: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Movie Header
                VStack(spacing: 12) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.orange)

                    Text(movieTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Text("Find showtimes near you")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 30)

                Divider()
                    .padding(.horizontal)

                // Search Options
                VStack(spacing: 12) {
                    TheaterLinkButton(
                        title: "Google Showtimes",
                        subtitle: "Search for nearby theaters",
                        icon: "magnifyingglass",
                        color: .blue
                    ) {
                        openURL("\(movieTitle) showtimes near me")
                    }

                    TheaterLinkButton(
                        title: "Fandango",
                        subtitle: "Buy tickets online",
                        icon: "ticket",
                        color: .orange
                    ) {
                        if let encoded = movieTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                           let url = URL(string: "https://www.fandango.com/search?q=\(encoded)") {
                            UIApplication.shared.open(url)
                        }
                    }

                    TheaterLinkButton(
                        title: "AMC Theatres",
                        subtitle: "Check AMC locations",
                        icon: "film",
                        color: .red
                    ) {
                        if let encoded = movieTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                           let url = URL(string: "https://www.amctheatres.com/movies?query=\(encoded)") {
                            UIApplication.shared.open(url)
                        }
                    }

                    TheaterLinkButton(
                        title: "Atom Tickets",
                        subtitle: "Mobile ticketing",
                        icon: "iphone",
                        color: .purple
                    ) {
                        if let encoded = movieTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                           let url = URL(string: "https://www.atomtickets.com/search?query=\(encoded)") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Showtimes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func openURL(_ query: String) {
        if let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }
}

struct TheaterLinkButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
#else
// macOS stub
struct ShowtimesSheet: View {
    let movieTitle: String

    var body: some View {
        Text("Showtimes not available on macOS")
    }
}
#endif
