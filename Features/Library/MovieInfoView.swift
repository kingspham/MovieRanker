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
    @Query private var allLogs: [LogEntry]
    
    @State private var showSuccessMessage = false
    @State private var successMessageText = "Saved"
    @State private var userId: String = "guest"
    
    enum ActiveSheet: Identifiable {
        case browser(URL)
        case share(PlatformImage)
        case log(Movie)
        case ranking(Movie)
        var id: String {
            switch self {
            case .browser: return "browser"
            case .share: return "share"
            case .log: return "log"
            case .ranking: return "ranking"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?
    
    @State private var showCreateListAlert = false
    @State private var newListName = ""
    @Query private var myLists: [CustomList]
    @Query private var allScores: [Score]
    
    var myScore: Int? {
        guard let m = movie else { return nil }
        return allScores.first(where: { $0.movieID == m.id && $0.ownerId == userId })?.display100
    }
    var hasRanked: Bool { myScore != nil }
    
    var myLog: LogEntry? {
        guard let m = movie else { return nil }
        return allLogs.first(where: { $0.movie?.id == m.id && $0.ownerId == userId })
    }
    
    var isInTheaters: Bool {
        guard let y = tmdb.year, mediaType == "movie" else { return false }
        let currentYear = Calendar.current.component(.year, from: Date())
        return y >= currentYear - 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 1. HERO
                HStack(alignment: .top, spacing: 16) {
                    PosterThumb(posterPath: tmdb.posterPath, title: tmdb.displayTitle, width: 120).shadow(radius: 8)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tmdb.displayTitle).font(.title3).fontWeight(.black)
                        if let genres = movie?.genreIDs, !genres.isEmpty {
                            Text(genres.map(genreIDToString).prefix(3).joined(separator: " • "))
                                .font(.caption).bold().foregroundStyle(.secondary)
                        }
                        if let y = tmdb.year {
                            Text(mediaType == "tv" ? "TV Series • \(y)" : String(y))
                                .foregroundStyle(.secondary).font(.subheadline)
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
                }.padding(.horizontal)

                // 2. SCORE/PREDICTION
                VStack(spacing: 12) {
                    if let score = myScore {
                        HStack(spacing: 12) {
                            ZStack { Circle().stroke(Color.blue, lineWidth: 4).frame(width: 50, height: 50); Text("\(score)").font(.headline).fontWeight(.black).foregroundStyle(.blue) }
                            VStack(alignment: .leading, spacing: 2) { Text("Your Score").font(.caption).textCase(.uppercase).foregroundStyle(.secondary); Text("Ranked on Leaderboard").font(.caption2).foregroundStyle(.secondary) }
                            Spacer()
                        }.padding(.horizontal)
                    } else if let pred = prediction {
                        HStack(spacing: 12) {
                            ZStack { Circle().stroke(Color.purple, lineWidth: 4).frame(width: 50, height: 50); Text("\(Int(pred.score * 10))").font(.headline).fontWeight(.black).foregroundStyle(.purple) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Predicted Score").font(.caption).textCase(.uppercase).foregroundStyle(.secondary)
                                if !pred.reasons.isEmpty {
                                    Text(pred.reasons.first ?? "Based on your tastes").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }.padding(.horizontal)
                    }
                }

                // 3. ACTIONS
                HStack(spacing: 12) {
                    if hasRanked {
                        Button { handleReRank() } label: { Text("Re-Rank").fontWeight(.bold).frame(maxWidth: .infinity).padding(.vertical, 14).background(Color.orange).foregroundColor(.white).cornerRadius(12) }
                    } else {
                        Button {
                            if let m = movie { activeSheet = .log(m) }
                        } label: {
                            Text("Mark as Watched").fontWeight(.bold).frame(maxWidth: .infinity).padding(.vertical, 14).background(Color.accentColor).foregroundColor(.white).cornerRadius(12)
                        }
                    }
                    Button { Task { await saveToWatchlist() } } label: { Text("Want to Watch").fontWeight(.bold).frame(maxWidth: .infinity).padding(.vertical, 14).background(Color.gray.opacity(0.15)).foregroundColor(.primary).cornerRadius(12) }
                    Menu { Text("Add to List"); ForEach(myLists.filter { $0.ownerId == userId }) { list in Button { Task { await addToList(list) } } label: { Label(list.name, systemImage: "list.bullet") } }; Divider(); Button { showCreateListAlert = true } label: { Label("Create New List", systemImage: "plus") } } label: { Image(systemName: "ellipsis").font(.title3).frame(width: 50, height: 50).background(Color.gray.opacity(0.15)).foregroundColor(.primary).cornerRadius(12) }
                }.padding(.horizontal)

                Divider().padding(.horizontal)
                
                // 4. TV SEASONS
                if mediaType == "tv" && !tvSeasons.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Seasons").font(.headline).padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 16) { ForEach(tvSeasons) { season in NavigationLink { MovieInfoView(tmdb: TMDbItem(id: season.id, title: "\(tmdb.displayTitle): \(season.name)", overview: "Season \(season.seasonNumber)", releaseDate: season.airDate, posterPath: season.posterPath ?? tmdb.posterPath, genreIds: tmdb.genreIds, mediaType: "tv"), mediaType: "tv").modelContext(context) } label: { VStack { PosterThumb(posterPath: season.posterPath ?? tmdb.posterPath, title: season.name, width: 100).shadow(radius: 4); Text(season.name).font(.caption).bold().foregroundStyle(.primary); Text("\(season.episodeCount ?? 0) eps").font(.caption2).foregroundStyle(.secondary) } } } }.padding(.horizontal) }
                    }
                    Divider().padding(.horizontal)
                }
                
                // 5. PROVIDERS
                if !providers.isEmpty {
                    VStack(alignment: .leading, spacing: 12) { Text("Where to Watch").font(.headline); ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 16) { ForEach(providers) { prov in Button { DeepLinkManager.open(providerName: prov.providerName, title: tmdb.displayTitle) { url in activeSheet = .browser(url) } } label: { if let logo = prov.logoPath, let url = TMDbClient.makeImageURL(path: logo, size: .w185) { AsyncImage(url: url) { phase in if let img = phase.image { img.resizable().scaledToFit() } else { Color.gray.opacity(0.2) } }.frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10)) } } } }.padding(.horizontal) } }
                }

                if let ov = tmdb.overview, !ov.isEmpty { VStack(alignment: .leading, spacing: 8) { Text("Overview").font(.headline); Text(ov).font(.body).foregroundStyle(.secondary).lineSpacing(4) }.padding(.horizontal) }
                
                if !cast.isEmpty { VStack(alignment: .leading, spacing: 12) { Text("Top Cast").font(.headline).padding(.horizontal); ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 16) { ForEach(cast.prefix(10)) { member in NavigationLink { PersonDetailView(personId: member.id, personName: member.name) } label: { VStack { AsyncImage(url: TMDbClient.makeImageURL(path: member.profilePath, size: .w185)) { phase in if let img = phase.image { img.resizable().scaledToFill() } else { Color.gray.opacity(0.3) } }.frame(width: 80, height: 80).clipShape(Circle()); Text(member.name).font(.caption).bold().multilineTextAlignment(.center).lineLimit(2).frame(width: 80).foregroundStyle(.primary); if let char = member.character { Text(char).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(1).frame(width: 80) } } } } }.padding(.horizontal) } } }
                Spacer(minLength: 50)
            }
        }
        .toolbar { ToolbarItem(placement: .primaryAction) { if hasRanked { Button { generateShareImage() } label: { Image(systemName: "square.and.arrow.up") } } } }
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
            case .log(let m):
                LogSheet(movie: m, showRanking: Binding(
                    get: { false },
                    set: { if $0 { activeSheet = .ranking(m) } }
                ))
            case .ranking(let m): RankingSheet(newMovie: m)
            }
        }
        .alert("Create List", isPresented: $showCreateListAlert) { TextField("List Name", text: $newListName); Button("Cancel", role: .cancel) { newListName = "" }; Button("Create & Add") { Task { await createAndAddList() } } }
        .task {
            userId = AuthService.shared.currentUserId() ?? "guest"
            
            if movie == nil {
                movie = Movie.findOrCreate(from: tmdb, type: mediaType, context: context, ownerId: userId)
            }
            
            if let m = movie {
                let engine = LinearPredictionEngine()
                self.prediction = engine.predict(for: m, in: context, userId: userId)
                if m.genreIDs.isEmpty { await selfHealGenres(for: m) }
            }
            
            do {
                let ratings = try await ExternalRatingsService.fetch(forTitle: tmdb.displayTitle, year: tmdb.year)
                self.externalRatings = ratings
            } catch {
                print("⚠️ Could not fetch external ratings: \(error)")
            }
            
            await loadRichDetails()
            await loadCredits()
            await loadProviders()
            if mediaType == "tv" { await loadSeasons() }
        }
        .overlay(alignment: .top) { if showSuccessMessage { SuccessToast(text: successMessageText) } }
    }
    
    // MARK: - Logic
    @MainActor private func generateShareImage() {
        guard let m = movie, let score = myScore else { return }
        
        #if os(iOS)
        let renderer = ImageRenderer(content: FlexCardView(movieTitle: m.title, posterPath: m.posterPath, score: score, rank: nil, username: "Me", avatarInitial: "M"))
        renderer.scale = 3.0
        if let image = renderer.uiImage { activeSheet = .share(image) }
        #endif
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
        
        let targetID: UUID? = movie.id
        let predicate = #Predicate<UserItem> { item in item.movie?.id == targetID }
        let items = (try? context.fetch(FetchDescriptor<UserItem>(predicate: predicate))) ?? []
        
        if !items.contains(where: { $0.state == .watchlist }) {
            let newItem = UserItem(movie: movie, state: .watchlist, ownerId: userId)
            context.insert(newItem)
            try? context.save()
            
            // 🆕 UPLOAD TO CLOUD!
            await SyncManager.shared.syncWatchlistAdd(movie: movie, item: newItem)
            
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
        if let score = allScores.first(where: { $0.movieID == m.id && $0.ownerId == userId }) {
            context.delete(score)
            try? context.save()
        }
        activeSheet = .ranking(m)
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
