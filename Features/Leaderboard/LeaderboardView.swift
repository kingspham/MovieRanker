// LeaderboardView.swift
import SwiftUI
import SwiftData

// NOTE: PlatformImage is already defined in MovieInfoView.swift, so we don't redefine it here.

struct LeaderboardView: View {
    @Environment(\.modelContext) private var context
    @State private var userId: String = "guest"

    @Query private var scores: [Score]
    @Query private var movies: [Movie]

    // STATE
    @State private var filter: MediaTypeFilter = .all
    @State private var sortOrder: SortOption = .rank
    @State private var selectedGenre: Int? = nil
    
    @State private var showReRankSheet = false
    @State private var movieToReRank: Movie?
    @State private var showQuickRank = false
    
    // SHARING
    @State private var showShareSheet = false
    // FIX: Use Any? to hold the image to avoid type errors
    @State private var shareItem: Any?
    
    @State private var isHealing = false

    // ENUMS
    enum MediaTypeFilter: String, CaseIterable, Identifiable {
        case all = "All"; case movies = "Movies"; case shows = "Shows"; case books = "Books"; case podcasts = "Podcasts"
        var id: String { rawValue }
    }
    
    enum SortOption: String, CaseIterable, Identifiable {
        case rank = "Rank"; case title = "Title"; case date = "Date Added"; case metacritic = "Metacritic"; case imdb = "IMDb"; case rottenTomatoes = "Rotten Tomatoes"
        var id: String { rawValue }
    }
    
    var myScores: [Score] { scores.filter { $0.ownerId == userId } }
    
    var unrankedCount: Int {
        let allLogs = (try? context.fetch(FetchDescriptor<LogEntry>())) ?? []
        let myLogs = allLogs.filter { $0.ownerId == userId || $0.ownerId == "guest" }
        let rankedMovieIDs = Set(myScores.map { $0.movieID })
        
        return myLogs.filter { log in
            guard let movieID = log.movie?.id else { return false }
            return !rankedMovieIDs.contains(movieID)
        }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                
                if myScores.count < 5 {
                    // Onboarding View if empty
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: "chart.bar.xaxis").font(.system(size: 60)).foregroundStyle(.gray)
                        Text("Start Ranking!").font(.title2).bold()
                        Text("Rate at least 5 items to see your leaderboard.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal)
                        Spacer()
                    }
                } else {
                    // NORMAL LEADERBOARD
                    Picker("", selection: $filter) { ForEach(MediaTypeFilter.allCases) { f in Text(f.rawValue).tag(f) } }.pickerStyle(.segmented).padding()
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            SortMenu(sortOrder: $sortOrder)
                            
                            // QUICK RANK BUTTON
                            if unrankedCount > 0 {
                                Button {
                                    showQuickRank = true
                                } label: {
                                    HStack {
                                        Image(systemName: "star.fill")
                                        Text("Quick Rank (\(unrankedCount))")
                                    }
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.green.opacity(0.1))
                                    .foregroundColor(.green)
                                    .cornerRadius(8)
                                }
                            }
                            
                            if isHealing { HStack { ProgressView().scaleEffect(0.6); Text("Updating...").font(.caption).foregroundStyle(.secondary) } }
                            
                            let availableGenres = getAvailableGenres()
                            ForEach(availableGenres, id: \.self) { genreId in
                                Button { if selectedGenre == genreId { selectedGenre = nil } else { selectedGenre = genreId } } label: { Text(genreIDToString(genreId)).font(.subheadline).bold().padding(.horizontal, 12).padding(.vertical, 8).background(selectedGenre == genreId ? Color.accentColor : Color.gray.opacity(0.1)).foregroundColor(selectedGenre == genreId ? .white : .primary).cornerRadius(20) }
                            }
                        }.padding(.horizontal)
                    }.padding(.bottom, 8)

                    Group {
                        let rows = getProcessedRows()
                        if rows.isEmpty { ContentUnavailableView("No results", systemImage: "magnifyingglass", description: Text("Try changing your filters.")) }
                        else {
                            List {
                                ForEach(rows) { row in
                                    Group {
                                        if row.mediaType == "book" { NavigationLink { BookInfoView(item: itemFromRow(row)).modelContext(context) } label: { RowContent(row: row) } }
                                        else if row.mediaType == "podcast" { NavigationLink { PodcastInfoView(item: itemFromRow(row)).modelContext(context) } label: { RowContent(row: row) } }
                                        else { NavigationLink { MovieInfoView(tmdb: itemFromRow(row), mediaType: row.mediaType).modelContext(context) } label: { RowContent(row: row) } }
                                    }
                                    .swipeActions(edge: .trailing) { Button(role: .destructive) { deleteScore(scoreID: row.id) } label: { Label("Delete", systemImage: "trash") } }
                                    .swipeActions(edge: .leading) { Button { prepareReRank(movieID: row.movieID, scoreID: row.id) } label: { Label("Re-Rank", systemImage: "arrow.triangle.2.circlepath") }.tint(.orange) }
                                }
                            }.listStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Leaderboard")
            // SHARE BUTTON
            .toolbar {
                if myScores.count >= 5 {
                    ToolbarItem(placement: .primaryAction) {
                        Button { shareTop10() } label: { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
            // SHEETS
            .sheet(isPresented: $showShareSheet) {
                if let item = shareItem { ShareSheet(items: [item]) }
            }
            .sheet(item: $movieToReRank) { movie in RankingSheet(newMovie: movie) }
            .sheet(isPresented: $showQuickRank) {
                BulkRankingView()
            }
            .task {
                let actor = AuthService.shared.sessionActor()
                userId = (try? await actor.session().userId) ?? "guest"
                await healMissingRatings()
            }
        }
    }
    
    // MARK: - Share Logic
    @MainActor private func shareTop10() {
        let rows = getProcessedRows()
        guard !rows.isEmpty else { return }
        
        #if os(iOS)
        let items = rows.prefix(10).map {
            FlexListView.FlexItem(rank: $0.rank, title: $0.title, posterPath: $0.posterPath, score: Int($0.score))
        }
        
        let renderer = ImageRenderer(content: FlexListView(
            title: "My Top \(filter.rawValue == "All" ? "Media" : filter.rawValue)",
            items: Array(items),
            username: "My Rankings"
        ))
        renderer.scale = 3.0
        
        if let image = renderer.uiImage {
            self.shareItem = image
            self.showShareSheet = true
        }
        #endif
    }
    
    // MARK: - Helpers & Logic
    private func healMissingRatings() async {
        let missing = movies.filter { ($0.mediaType == "movie" || $0.mediaType == "tv") && ($0.imdbRating == nil || $0.metaScore == nil) }
        guard !missing.isEmpty else { return }; isHealing = true
        let service = ShowDetailsService()
        for movie in missing.prefix(10) {
            if let details = try? await service.lookupByTitle(movie.title, year: movie.year) {
                movie.imdbRating = details.imdbRating; movie.metaScore = details.metascore; movie.rottenTomatoesRating = details.rottenTomatoes
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        try? context.save(); isHealing = false
    }
    private func RowContent(row: Row) -> some View {
        HStack(spacing: 12) {
            Text("#\(row.rank)").font(.caption).fontWeight(.bold).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
            PosterThumb(posterPath: row.posterPath, title: row.title, width: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.headline)
                if sortOrder == .metacritic, let meta = row.metaScore, meta != "N/A" { Text("Metascore: \(meta)").font(.caption).foregroundStyle(.green).bold() }
                else if sortOrder == .imdb, let imdb = row.imdbRating, imdb != "N/A" { Text("IMDb: \(imdb)").font(.caption).foregroundStyle(.yellow).bold() }
                else if sortOrder == .rottenTomatoes, let rt = row.rtRating { Text("RT: \(rt)").font(.caption).foregroundStyle(.red).bold() }
                else if let sub = row.subtitle { Text(sub).foregroundStyle(.secondary).font(.caption) }
            }
            Spacer()
            Text("\(Int(row.score))").font(.headline).monospacedDigit().foregroundStyle(Color.accentColor)
        }.padding(.vertical, 4)
    }
    private func sortIcon(for option: SortOption) -> String { switch option { case .rank: return "trophy"; case .title: return "textformat"; case .date: return "calendar"; default: return "star.circle" } }
    private func itemFromRow(_ row: Row) -> TMDbItem { return TMDbItem(id: row.tmdbID ?? 0, title: row.title, overview: nil, releaseDate: nil, posterPath: row.posterPath, genreIds: [], mediaType: row.mediaType) }
    private struct Row: Identifiable { let id: UUID; let movieID: UUID; let rank: Int; let title: String; let subtitle: String?; let posterPath: String?; let score: Double; let tmdbID: Int?; let mediaType: String; let dateAdded: Date; let genreIDs: [Int]; let metaScore: String?; let imdbRating: String?; let rtRating: String?; let year: Int? }
    private func getProcessedRows() -> [Row] {
        let moviesByID = Dictionary(uniqueKeysWithValues: movies.map { ($0.id, $0) })
        let myScores = scores.filter { $0.ownerId == userId }
        var bestScores: [UUID: Score] = [:]
        for s in myScores { if let existing = bestScores[s.movieID] { if s.display100 > existing.display100 { bestScores[s.movieID] = s } } else { bestScores[s.movieID] = s } }
        var rows: [Row] = []
        for s in bestScores.values {
            if let m = moviesByID[s.movieID] {
                if filter == .movies && m.mediaType != "movie" { continue }
                if filter == .shows && m.mediaType != "tv" { continue }
                if filter == .books && m.mediaType != "book" { continue }
                if filter == .podcasts && m.mediaType != "podcast" { continue }
                if let genre = selectedGenre { if !m.genreIDs.contains(genre) { if m.mediaType == "movie" || m.mediaType == "tv" { continue } } }
                if let decade = selectedDecade, let year = m.year { if decade == 1900 { if year >= 1980 { continue } } else { if year < decade || year >= decade + 10 { continue } } }
                var subtitle = m.year.map(String.init); if (m.mediaType == "book" || m.mediaType == "podcast"), let author = m.authors?.first { subtitle = author }
                rows.append(Row(id: s.id, movieID: m.id, rank: 0, title: m.title, subtitle: subtitle, posterPath: m.posterPath, score: Double(s.display100), tmdbID: m.tmdbID, mediaType: m.mediaType, dateAdded: m.createdAt, genreIDs: m.genreIDs, metaScore: m.metaScore, imdbRating: m.imdbRating, rtRating: m.rottenTomatoesRating, year: m.year))
            }
        }
        switch sortOrder { case .rank: rows.sort { $0.score > $1.score }; case .title: rows.sort { $0.title < $1.title }; case .date: rows.sort { $0.dateAdded > $1.dateAdded }; case .metacritic: rows.sort { (Int($0.metaScore ?? "0") ?? 0) > (Int($1.metaScore ?? "0") ?? 0) }; case .imdb: rows.sort { (Double($0.imdbRating ?? "0") ?? 0) > (Double($1.imdbRating ?? "0") ?? 0) }; case .rottenTomatoes: rows.sort { (Int($0.rtRating?.replacingOccurrences(of: "%", with: "") ?? "0") ?? 0) > (Int($1.rtRating?.replacingOccurrences(of: "%", with: "") ?? "0") ?? 0) } }
        var finalRows: [Row] = []; for (index, row) in rows.enumerated() { finalRows.append(Row(id: row.id, movieID: row.movieID, rank: index + 1, title: row.title, subtitle: row.subtitle, posterPath: row.posterPath, score: row.score, tmdbID: row.tmdbID, mediaType: row.mediaType, dateAdded: row.dateAdded, genreIDs: row.genreIDs, metaScore: row.metaScore, imdbRating: row.imdbRating, rtRating: row.rtRating, year: row.year)) }; return finalRows
    }
    private func getAvailableGenres() -> [Int] { let myMovies = movies.filter { $0.ownerId == userId }; var genreSet = Set<Int>(); for m in myMovies { if filter == .movies && m.mediaType != "movie" { continue }; if filter == .shows && m.mediaType != "tv" { continue }; for g in m.genreIDs { genreSet.insert(g) } }; return Array(genreSet).sorted() }
    private func deleteScore(scoreID: UUID) { if let score = scores.first(where: { $0.id == scoreID }) { context.delete(score); try? context.save() } }
    private func prepareReRank(movieID: UUID, scoreID: UUID) { if let movie = movies.first(where: { $0.id == movieID }) { deleteScore(scoreID: scoreID); movieToReRank = movie } }
    private func genreIDToString(_ id: Int) -> String { switch id { case 28: return "Action"; case 12: return "Adventure"; case 16: return "Animation"; case 35: return "Comedy"; case 80: return "Crime"; case 99: return "Documentary"; case 18: return "Drama"; case 10751: return "Family"; case 14: return "Fantasy"; case 36: return "History"; case 27: return "Horror"; case 10402: return "Music"; case 9648: return "Mystery"; case 10749: return "Romance"; case 878: return "Sci-Fi"; case 10770: return "TV Movie"; case 53: return "Thriller"; case 10752: return "War"; case 37: return "Western"; default: return "Genre" } }
    
    // DECADE FILTER
    @State private var selectedDecade: Int? = nil
}

struct SortMenu: View {
    @Binding var sortOrder: LeaderboardView.SortOption
    
    var body: some View {
        Menu {
            Picker("Sort By", selection: $sortOrder) {
                ForEach(LeaderboardView.SortOption.allCases) { option in
                    Label(option.rawValue, systemImage: "line.3.horizontal.decrease").tag(option)
                }
            }
        } label: {
            HStack {
                Image(systemName: "arrow.up.arrow.down")
                Text(sortOrder.rawValue)
            }
            .font(.subheadline).bold()
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .foregroundColor(.primary)
            .cornerRadius(20)
        }
    }
}
