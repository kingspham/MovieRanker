import SwiftUI
import SwiftData

struct PublicProfileView: View {
    let profile: SocialProfile

    @Environment(\.modelContext) private var context
    @State private var items: [PublicLog] = []
    @State private var stats: PublicStats?
    @State private var isLoading = true
    @State private var isFollowing = false

    // Viewership Intersection
    @State private var sharedCount: Int = 0
    @State private var theirTotal: Int = 0

    // Taste Profile
    @State private var theirTopGenres: [(name: String, count: Int)] = []
    @State private var tasteSimilarity: Int = 0 // 0-100%

    // Follow counts
    @State private var followerCount: Int = 0
    @State private var followingCount: Int = 0

    @State private var myId: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Circle().fill(Color.gray.opacity(0.2)).frame(width: 100, height: 100)
                        .overlay(Text(String(profile.displayName.prefix(1)).uppercased()).font(.largeTitle).bold())

                    Text(profile.displayName).font(.title2).bold()
                    Text("@\(profile.username ?? "user")").foregroundStyle(.secondary)

                    // Bio
                    if let bio = profile.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    // Location
                    if let city = profile.homeCity, !city.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.red)
                            Text(city)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Don't show follow button for yourself
                    if profile.id.uuidString != myId {
                        Button(isFollowing ? "Following" : "Follow") {
                            Task { await toggleFollow() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isFollowing ? .gray : .blue)
                    }
                }
                .padding(.top)

                // STATS ROW - Clickable stats
                if !isLoading {
                    HStack(spacing: 24) {
                        NavigationLink(destination: UserRankedListView(profile: profile, items: items)) {
                            VStack {
                                Text("\(stats?.totalLogs ?? 0)").font(.headline)
                                Text("Ranked").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        NavigationLink(destination: FollowListView(userId: profile.id.uuidString, mode: .followers)) {
                            VStack {
                                Text("\(followerCount)").font(.headline)
                                Text("Followers").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        NavigationLink(destination: FollowListView(userId: profile.id.uuidString, mode: .following)) {
                            VStack {
                                Text("\(followingCount)").font(.headline)
                                Text("Following").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        NavigationLink(destination: InCommonView(profile: profile, items: items, myId: myId)) {
                            VStack {
                                Text("\(sharedCount)").font(.headline)
                                Text("In Common").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(12)
                }

                // TASTE SIMILARITY
                if !isLoading && tasteSimilarity > 0 {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Taste Similarity")
                                .font(.headline)
                            Spacer()
                            Text("\(tasteSimilarity)%")
                                .font(.title2)
                                .bold()
                                .foregroundStyle(similarityColor)
                        }
                        .padding(.horizontal)

                        // Similarity bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.2))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(similarityColor)
                                    .frame(width: geo.size.width * CGFloat(tasteSimilarity) / 100)
                            }
                        }
                        .frame(height: 8)
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // FAVORITES
                if hasFavorites {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Favorites").font(.headline).padding(.horizontal)
                        if let movie = profile.favoriteMovie, !movie.isEmpty {
                            favoriteRow(icon: "film.fill", color: .blue, label: "Movie", value: movie)
                        }
                        if let show = profile.favoriteShow, !show.isEmpty {
                            favoriteRow(icon: "tv.fill", color: .purple, label: "TV Show", value: show)
                        }
                        if let book = profile.favoriteBook, !book.isEmpty {
                            favoriteRow(icon: "book.fill", color: .orange, label: "Book", value: book)
                        }
                        if let podcast = profile.favoritePodcast, !podcast.isEmpty {
                            favoriteRow(icon: "mic.fill", color: .green, label: "Podcast", value: podcast)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // TASTE PROFILE
                if !theirTopGenres.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Top Genres").font(.headline).padding(.horizontal)
                        ForEach(theirTopGenres.prefix(5), id: \.name) { genre in
                            HStack {
                                Text(genre.name)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(genre.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Recent Activity
                VStack(alignment: .leading) {
                    Text("Recent Activity").font(.headline).padding(.horizontal)

                    if items.isEmpty {
                        ContentUnavailableView("No activity", systemImage: "clock")
                    } else {
                        ForEach(items.prefix(10)) { item in
                            HStack {
                                if let url = item.posterURL {
                                    AsyncImage(url: url) { $0.image?.resizable().scaledToFill() }
                                        .frame(width: 50, height: 75).cornerRadius(8)
                                } else {
                                    Rectangle().fill(Color.gray.opacity(0.3))
                                        .frame(width: 50, height: 75).cornerRadius(8)
                                }
                                VStack(alignment: .leading) {
                                    Text(item.title).bold()
                                    if let s = item.score { Text("Score: \(s)").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                Spacer(minLength: 50)
            }
        }
        .navigationTitle(profile.username ?? "Profile")
        .task {
            await loadPublicData()
            await checkFollowStatus()
            await loadFollowCounts()
        }
    }

    private var hasFavorites: Bool {
        profile.favoriteMovie != nil || profile.favoriteShow != nil ||
        profile.favoriteBook != nil || profile.favoritePodcast != nil
    }

    private var similarityColor: Color {
        if tasteSimilarity >= 70 { return .green }
        if tasteSimilarity >= 40 { return .orange }
        return .red
    }

    private func favoriteRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal)
    }

    private func loadPublicData() async {
        let fetchedItems = await FeedService.shared.fetchUserLogs(userId: profile.id.uuidString)
        let session = try? await AuthService.shared.sessionActor().session()
        let currentUserId = session?.userId ?? ""

        await MainActor.run {
            self.items = fetchedItems
            self.myId = currentUserId

            // Get My Movies to compare
            let allMovies = (try? context.fetch(FetchDescriptor<Movie>())) ?? []
            let myMovies = allMovies.filter { $0.ownerId == currentUserId }
            let myIDs = Set(myMovies.compactMap { $0.tmdbID })

            let theirIDs = Set(fetchedItems.map { $0.tmdbID })

            self.theirTotal = theirIDs.count
            self.sharedCount = theirIDs.intersection(myIDs).count
            self.stats = PublicStats(totalLogs: fetchedItems.count)

            // Calculate their taste profile
            calculateTheirTaste(items: fetchedItems)

            // Calculate taste similarity based on genres
            calculateTasteSimilarity(myMovies: myMovies)

            self.isLoading = false
        }
    }

    private func calculateTheirTaste(items: [PublicLog]) {
        // This would require genre IDs from the items - for now we'll show based on available data
        // In a real implementation, you'd fetch genre data for their logs
        let genreCounts: [String: Int] = [:]

        // Simple implementation - this would be enhanced with actual genre data
        for _ in items {
            // You'd look up genre IDs here from their logs
            // For now, this serves as a placeholder
        }

        theirTopGenres = genreCounts.sorted { $0.value > $1.value }.map { (name: $0.key, count: $0.value) }
    }

    private func calculateTasteSimilarity(myMovies: [Movie]) {
        // Calculate taste similarity based on:
        // 1. Rating agreement on shared movies (weighted heavily)
        // 2. Genre overlap (lighter weight)
        guard !items.isEmpty else { return }

        // Get my scores for comparison
        let allScores = (try? context.fetch(FetchDescriptor<Score>())) ?? []
        let myScores = allScores.filter { $0.ownerId == myId }
        let myScoreLookup = Dictionary(uniqueKeysWithValues: myScores.compactMap { score -> (Int, Int)? in
            guard let movie = myMovies.first(where: { $0.id == score.movieID }),
                  let tmdbID = movie.tmdbID else { return nil }
            return (tmdbID, score.display100)
        })

        // Calculate rating similarity for shared movies
        var ratingDifferences: [Double] = []
        for theirLog in items {
            guard let theirScore = theirLog.score,
                  let myScore = myScoreLookup[theirLog.tmdbID] else { continue }

            // Calculate difference (0-100 scale)
            let diff = abs(Double(myScore) - Double(theirScore))
            ratingDifferences.append(diff)
        }

        var similarity: Double = 0

        if !ratingDifferences.isEmpty {
            // Average rating difference
            let avgDiff = ratingDifferences.reduce(0, +) / Double(ratingDifferences.count)

            // Convert to similarity (0-100)
            // Max diff is 100, so (100 - avgDiff) / 100 gives 0-1
            let ratingSimilarity = max(0, (100 - avgDiff)) / 100

            // Weight: 70% rating agreement, 30% shared ratio
            let sharedRatio = theirTotal > 0 ? Double(sharedCount) / Double(min(theirTotal, myMovies.count)) : 0

            similarity = (ratingSimilarity * 0.7 + sharedRatio * 0.3) * 100
        } else if sharedCount > 0 {
            // No ratings to compare, but have shared movies - use genre overlap
            var myGenreCounts: [Int: Int] = [:]
            for movie in myMovies {
                for genreId in movie.genreIDs {
                    myGenreCounts[genreId, default: 0] += 1
                }
            }

            // Use shared ratio with a penalty for no rating data
            let sharedRatio = theirTotal > 0 ? Double(sharedCount) / Double(min(theirTotal, myMovies.count)) : 0
            similarity = sharedRatio * 50 // Cap at 50% without rating data
        }

        tasteSimilarity = Int(min(100, max(0, similarity)))
    }

    private func loadFollowCounts() async {
        let counts = await SocialService.shared.getFollowCounts(userId: profile.id.uuidString)
        await MainActor.run {
            self.followerCount = counts.followers
            self.followingCount = counts.following
        }
    }

    private func checkFollowStatus() async {
        let following = await SocialService.shared.fetchFollowing(userId: myId)
        isFollowing = following.contains { $0.id == profile.id }
    }

    private func toggleFollow() async {
        let targetId = profile.id.uuidString

        if isFollowing {
            try? await SocialService.shared.unfollow(targetId: targetId)
        } else {
            try? await SocialService.shared.follow(targetId: targetId)
        }
        isFollowing.toggle()
    }
}

struct PublicStats {
    let totalLogs: Int
}

struct PublicLog: Identifiable {
    let id: UUID
    let title: String
    let posterPath: String?
    let score: Int?
    let tmdbID: Int
    let mediaType: String?

    init(id: UUID, title: String, posterPath: String?, score: Int?, tmdbID: Int, mediaType: String? = "movie") {
        self.id = id
        self.title = title
        self.posterPath = posterPath
        self.score = score
        self.tmdbID = tmdbID
        self.mediaType = mediaType
    }

    var posterURL: URL? {
        TMDbClient.makeImageURL(path: posterPath ?? "", size: .w185)
    }
}

// MARK: - User's Ranked List View
struct UserRankedListView: View {
    let profile: SocialProfile
    let items: [PublicLog]

    var sortedItems: [PublicLog] {
        items.sorted { ($0.score ?? 0) > ($1.score ?? 0) }
    }

    var body: some View {
        List {
            ForEach(sortedItems) { item in
                NavigationLink {
                    let tmdbItem = TMDbItem(id: item.tmdbID, title: item.title, posterPath: item.posterPath, mediaType: item.mediaType ?? "movie")
                    MovieInfoView(tmdb: tmdbItem, mediaType: item.mediaType ?? "movie")
                } label: {
                    HStack(spacing: 12) {
                        if let url = item.posterURL {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image { img.resizable().scaledToFill() }
                                else { Color.gray.opacity(0.2) }
                            }
                            .frame(width: 50, height: 75)
                            .cornerRadius(6)
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 50, height: 75)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.headline)
                                .lineLimit(2)
                        }

                        Spacer()

                        if let score = item.score {
                            ZStack {
                                Circle()
                                    .stroke(scoreColor(score), lineWidth: 3)
                                    .frame(width: 40, height: 40)
                                Text("\(score)")
                                    .font(.caption)
                                    .fontWeight(.black)
                                    .foregroundStyle(scoreColor(score))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("\(profile.displayName)'s Rankings")
        .listStyle(.plain)
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 90 { return .green }
        if score >= 70 { return .blue }
        if score >= 50 { return .orange }
        return .red
    }
}

// MARK: - In Common View
struct InCommonView: View {
    let profile: SocialProfile
    let items: [PublicLog]
    let myId: String

    @Environment(\.modelContext) private var context

    var inCommonItems: [PublicLog] {
        let allMovies = (try? context.fetch(FetchDescriptor<Movie>())) ?? []
        let myMovies = allMovies.filter { $0.ownerId == myId }
        let myTmdbIDs = Set(myMovies.compactMap { $0.tmdbID })
        return items.filter { myTmdbIDs.contains($0.tmdbID) }
    }

    var body: some View {
        Group {
            if inCommonItems.isEmpty {
                ContentUnavailableView(
                    "Nothing in Common Yet",
                    systemImage: "person.2.slash",
                    description: Text("Watch more movies to find what you have in common!")
                )
            } else {
                List {
                    ForEach(inCommonItems) { item in
                        NavigationLink {
                            let tmdbItem = TMDbItem(id: item.tmdbID, title: item.title, posterPath: item.posterPath, mediaType: item.mediaType ?? "movie")
                            MovieInfoView(tmdb: tmdbItem, mediaType: item.mediaType ?? "movie")
                        } label: {
                            HStack(spacing: 12) {
                                if let url = item.posterURL {
                                    AsyncImage(url: url) { phase in
                                        if let img = phase.image { img.resizable().scaledToFill() }
                                        else { Color.gray.opacity(0.2) }
                                    }
                                    .frame(width: 50, height: 75)
                                    .cornerRadius(6)
                                } else {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 50, height: 75)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.headline)
                                        .lineLimit(2)
                                    if let score = item.score {
                                        Text("\(profile.displayName) rated: \(score)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("In Common")
    }
}
