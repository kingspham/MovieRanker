// RapidFireView.swift
import SwiftUI
import SwiftData

struct RapidFireView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @State private var cards: [TMDbItem] = []
    @State private var userId: String = "guest"
    @State private var isLoading = true

    // To trigger Ranking
    @State private var movieToRank: Movie?

    // Feedback toast
    @State private var lastRatedTitle: String = ""
    @State private var lastRatedScore: Int = 0
    @State private var showRatingToast = false

    // Avoid @Query crash
    @State private var seenTMDBIds: Set<Int> = []
    
    var body: some View {
        NavigationStack {
            ZStack {
                // FIX: Replaced UIKit color with a standard SwiftUI color
                Color.gray.opacity(0.1).ignoresSafeArea()
                
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                        Text("Finding movies...").multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }
                } else if cards.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 60)).foregroundStyle(.green)
                        Text("All Caught Up!").font(.title).bold()
                        Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                    }.padding()
                } else {
                    ZStack {
                        ForEach(cards.prefix(3).reversed(), id: \.id) { item in
                            RapidCard(item: item) { direction in handleSwipe(item: item, direction: direction) }
                        }
                    }
                    
                    // BUTTONS
                    VStack {
                        Spacer()
                        HStack(spacing: 40) {
                            // Dislike / Skip (Left)
                            Button {
                                if let top = cards.first { handleSwipe(item: top, direction: .left) }
                            } label: {
                                VStack { Image(systemName: "eye.slash.fill").font(.title).foregroundStyle(.gray); Text("Skip").font(.caption2).bold() }
                            }
                            
                            // Watchlist (Up)
                            Button {
                                if let top = cards.first { handleSwipe(item: top, direction: .up) }
                            } label: {
                                VStack { Image(systemName: "bookmark.fill").font(.title).foregroundStyle(.blue); Text("Watchlist").font(.caption2).bold() }
                            }
                            
                            // Like / Rate (Right)
                            Button {
                                if let top = cards.first { handleSwipe(item: top, direction: .right) }
                            } label: {
                                VStack { Image(systemName: "star.fill").font(.title).foregroundStyle(.green); Text("Seen / Rate").font(.caption2).bold() }
                            }
                        }
                        .padding(.bottom, 40)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Rapid Fire")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .sheet(item: $movieToRank) { movie in
                RankingSheet(newMovie: movie)
            }
            .onChange(of: movieToRank) { oldValue, newValue in
                // When ranking sheet is dismissed, show feedback toast
                if oldValue != nil && newValue == nil {
                    // Find the score that was just created
                    let allScores = (try? context.fetch(FetchDescriptor<Score>())) ?? []
                    if let score = allScores.first(where: { $0.movieID == oldValue?.id && $0.ownerId == userId }) {
                        lastRatedTitle = oldValue?.title ?? "Movie"
                        lastRatedScore = score.display100
                        showRatingToast = true
                        // Auto-hide after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            showRatingToast = false
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                if showRatingToast {
                    RatingToast(title: lastRatedTitle, score: lastRatedScore)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(), value: showRatingToast)
                }
            }
            .task {
                let actor = AuthService.shared.sessionActor()
                if let s = try? await actor.session() { userId = s.userId }
                await loadData()
            }
        }
    }
    
    func handleSwipe(item: TMDbItem, direction: SwipeDirection) {
        withAnimation { if let idx = cards.firstIndex(where: { $0.id == item.id }) { cards.remove(at: idx) } }
        seenTMDBIds.insert(item.id)
        
        switch direction {
        case .left, .down:
            // Just skip
            break
        case .up:
            saveMovie(item: item, state: .watchlist, triggerRanking: false)
        case .right:
            // "Seen" -> Trigger Ranking
            saveMovie(item: item, state: .seen, triggerRanking: true)
        }
        
        if cards.count < 3 { Task { await fetchMoreCards() } }
    }
    
    private func saveMovie(item: TMDbItem, state: UserItem.State, triggerRanking: Bool) {
        let tmdbID = item.id
        var targetMovie: Movie

        // 1. Find or Create Movie (filter in memory - predicates have issues)
        let allMovies = (try? context.fetch(FetchDescriptor<Movie>())) ?? []
        if let existing = allMovies.first(where: { $0.tmdbID == tmdbID }) {
            targetMovie = existing
        } else {
            let new = Movie(
                title: item.displayTitle,
                year: item.year,
                tmdbID: item.id,
                posterPath: item.posterPath,
                genreIDs: item.genreIds ?? [],
                mediaType: "movie",
                ownerId: userId
            )
            context.insert(new)
            targetMovie = new
        }
        
        // 2. Create UserItem
        let uItem = UserItem(movie: targetMovie, state: state, ownerId: userId)
        context.insert(uItem)
        try? context.save()
        
        // 3. Trigger Ranking if needed
        if triggerRanking {
            self.movieToRank = targetMovie
        }
    }
    
    func loadData() async {
        // FIX: Exclude movies that user has RATED, not just "owned"
        let allMovies = (try? context.fetch(FetchDescriptor<Movie>())) ?? []

        // Get all scores for this user
        let allScores = (try? context.fetch(FetchDescriptor<Score>())) ?? []
        let userScoreMovieIDs = Set(allScores.filter { $0.ownerId == userId || $0.ownerId == "guest" }.map { $0.movieID })

        // Get TMDb IDs of rated movies
        let ratedTMDbIds = allMovies
            .filter { userScoreMovieIDs.contains($0.id) }
            .compactMap { $0.tmdbID }

        // Also exclude movies in user's library (watchlist, seen, etc.)
        let userMovieTMDbIds = allMovies
            .filter { $0.ownerId == userId || $0.ownerId == "guest" }
            .compactMap { $0.tmdbID }

        // Combine both sets - exclude rated AND library items
        self.seenTMDBIds = Set(ratedTMDbIds + userMovieTMDbIds)

        print("📋 Rapid Fire: Excluding \(seenTMDBIds.count) already-seen/rated movies")
        await fetchMoreCards()
    }
    
    func fetchMoreCards() async {
        guard let client = try? TMDbClient() else { return }
        var newCards: [TMDbItem] = []
        for _ in 0..<3 {
            let page = Int.random(in: 1...20)
            if let resp = try? await client.popularMovies(page: page) {
                let filtered = resp.results.filter { m in
                    !seenTMDBIds.contains(m.id) && !cards.contains(where: { c in c.id == m.id })
                }
                newCards.append(contentsOf: filtered)
            }
        }
        let uniqueCards = Array(NSOrderedSet(array: newCards)) as! [TMDbItem]
        self.cards.append(contentsOf: uniqueCards.shuffled())
        self.isLoading = false
    }
}

// (Components kept same)
enum SwipeDirection { case left, right, up, down }
struct RapidCard: View {
    let item: TMDbItem
    let onSwipe: (SwipeDirection) -> Void
    @State private var offset: CGSize = .zero
    var body: some View {
        ZStack {
            if let path = item.posterPath { AsyncImage(url: TMDbClient.makeImageURL(path: path, size: .w500)) { p in if let i = p.image { i.resizable().scaledToFill() } else { Color.gray } } } else { Color.gray }
            VStack { Spacer(); LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom).frame(height: 200) }
            VStack(alignment: .leading) { Spacer(); Text(item.displayTitle).font(.title).fontWeight(.heavy).foregroundStyle(.white).shadow(radius: 4); if let y = item.year { Text(String(y)).font(.headline).foregroundStyle(.white.opacity(0.8)).shadow(radius: 4) } }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            if offset.width > 50 { Image(systemName: "star.fill").font(.system(size: 80)).foregroundStyle(.green).opacity(0.8) }
            else if offset.width < -50 { Image(systemName: "eye.slash.fill").font(.system(size: 80)).foregroundStyle(.gray).opacity(0.8) }
            else if offset.height < -50 { Image(systemName: "bookmark.fill").font(.system(size: 80)).foregroundStyle(.blue).opacity(0.8) }
        }
        .frame(width: 340, height: 520).cornerRadius(24).shadow(radius: 10, x: 0, y: 5).offset(x: offset.width, y: offset.height).rotationEffect(.degrees(Double(offset.width / 15))).gesture(DragGesture().onChanged { offset = $0.translation }.onEnded { gesture in let width = gesture.translation.width; let height = gesture.translation.height; if abs(width) > abs(height) { if width > 150 { onSwipe(.right) } else if width < -150 { onSwipe(.left) } else { withAnimation(.spring()) { offset = .zero } } } else { if height < -150 { onSwipe(.up) } else if height > 150 { onSwipe(.down) } else { withAnimation(.spring()) { offset = .zero } } } })
    }
}

struct RatingToast: View {
    let title: String
    let score: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Rated!")
                    .font(.headline)
                Text("\(title): \(score)/100")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 4)
        .padding(.horizontal)
        .padding(.top, 8)
    }
}
