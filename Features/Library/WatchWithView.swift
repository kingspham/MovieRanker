// WatchWithView.swift
// "Watch With" feature - Compare predicted scores with a friend

import SwiftUI
import SwiftData

struct WatchWithSheet: View {
    let movie: Movie
    let tmdb: TMDbItem
    let myScoreValue: Int?
    let myPrediction: PredictionExplanation?
    let userId: String

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var friends: [SocialProfile] = []
    @State private var selectedFriend: SocialProfile?
    @State private var friendPrediction: PredictionExplanation?
    @State private var friendActualScore: Int?
    @State private var isLoadingFriends = true
    @State private var isLoadingPrediction = false

    var body: some View {
        NavigationStack {
            Group {
                if selectedFriend == nil {
                    friendPickerView
                } else {
                    comparisonView
                }
            }
            .navigationTitle(L10n.watchWith)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
            }
        }
    }

    // MARK: - Friend Picker

    private var friendPickerView: some View {
        Group {
            if isLoadingFriends {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text(L10n.isSpanish ? "Cargando amigos..." : "Loading friends...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if friends.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                    Text(L10n.noFriendsYet)
                        .font(.headline)
                    Text(L10n.noFriendsDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
            } else {
                List {
                    // Movie header
                    Section {
                        HStack(spacing: 12) {
                            PosterThumb(posterPath: tmdb.posterPath, title: tmdb.displayTitle, width: 50)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tmdb.displayTitle)
                                    .font(.headline)
                                if let y = tmdb.year {
                                    Text(String(y))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // Friends list
                    Section {
                        ForEach(friends) { friend in
                            Button {
                                selectedFriend = friend
                                Task { await loadFriendPrediction(friend: friend) }
                            } label: {
                                HStack(spacing: 12) {
                                    // Avatar circle
                                    ZStack {
                                        Circle()
                                            .fill(Color.purple.opacity(0.15))
                                            .frame(width: 40, height: 40)
                                        Text(String(friend.displayName.prefix(1)).uppercased())
                                            .font(.headline)
                                            .foregroundStyle(.purple)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(friend.displayName)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        if let username = friend.username {
                                            Text("@\(username)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text(L10n.pickAFriend)
                    }
                }
            }
        }
        .task {
            await loadFriends()
        }
    }

    // MARK: - Comparison View

    private var comparisonView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Movie header
                VStack(spacing: 12) {
                    PosterThumb(posterPath: tmdb.posterPath, title: tmdb.displayTitle, width: 100)
                        .shadow(radius: 8)
                    Text(tmdb.displayTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    if let y = tmdb.year {
                        Text(String(y))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 16)

                Divider()
                    .padding(.horizontal)

                // Score comparison
                if isLoadingPrediction {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(L10n.calculatingPrediction)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 30)
                } else {
                    // Side-by-side scores
                    HStack(spacing: 24) {
                        // My score
                        scoreColumn(
                            label: L10n.you,
                            score: myScoreValue ?? (myPrediction != nil ? Int(myPrediction!.score * 10) : nil),
                            isPredicted: myScoreValue == nil,
                            color: .blue,
                            initial: "M"
                        )

                        // VS
                        VStack {
                            Text("VS")
                                .font(.caption)
                                .fontWeight(.black)
                                .foregroundStyle(.secondary)
                        }

                        // Friend's score
                        if let friend = selectedFriend {
                            scoreColumn(
                                label: friend.displayName,
                                score: friendActualScore ?? (friendPrediction != nil ? Int(friendPrediction!.score * 10) : nil),
                                isPredicted: friendActualScore == nil,
                                color: .purple,
                                initial: String(friend.displayName.prefix(1))
                            )
                        }
                    }
                    .padding(.vertical, 20)

                    // Compatibility indicator
                    if let myVal = myScoreValue ?? (myPrediction != nil ? Int(myPrediction!.score * 10) : nil),
                       let friendVal = friendActualScore ?? (friendPrediction != nil ? Int(friendPrediction!.score * 10) : nil) {
                        compatibilityView(myScore: myVal, friendScore: friendVal)
                    }

                    // Friend's prediction reasons
                    if friendActualScore == nil, let pred = friendPrediction, !pred.reasons.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            if let friend = selectedFriend {
                                Text(L10n.isSpanish
                                    ? "Por qué \(friend.displayName) podría calificarlo así"
                                    : "Why \(friend.displayName) might rate it this way")
                                    .font(.caption)
                                    .textCase(.uppercase)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(pred.reasons.prefix(3), id: \.self) { reason in
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkle")
                                        .font(.caption2)
                                        .foregroundStyle(.purple)
                                    Text(reason)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color.purple.opacity(0.05))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    // If friend has an actual score, note it
                    if friendActualScore != nil {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text(L10n.isSpanish
                                ? "Tu amigo ya calificó esta película"
                                : "Your friend already rated this one")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }
                }

                // Change friend button
                Button {
                    selectedFriend = nil
                    friendPrediction = nil
                    friendActualScore = nil
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2")
                        Text(L10n.chooseDifferentFriend)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                }
                .padding(.top, 10)

                Spacer(minLength: 30)
            }
        }
    }

    // MARK: - Score Column

    private func scoreColumn(label: String, score: Int?, isPredicted: Bool, color: Color, initial: String) -> some View {
        VStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 56, height: 56)
                Text(initial.uppercased())
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
            }

            // Name
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .frame(width: 100)

            // Score circle
            if let score = score {
                ZStack {
                    Circle()
                        .stroke(color, lineWidth: 4)
                        .frame(width: 64, height: 64)
                    VStack(spacing: 0) {
                        Text("\(score)")
                            .font(.title2)
                            .fontWeight(.black)
                            .foregroundStyle(color)
                        if isPredicted {
                            Text(L10n.predicted)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                        .frame(width: 64, height: 64)
                    Text("--")
                        .font(.title2)
                        .fontWeight(.black)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Compatibility View

    private func compatibilityView(myScore: Int, friendScore: Int) -> some View {
        let average = (myScore + friendScore) / 2
        let difference = abs(myScore - friendScore)

        let emoji: String
        let message: String

        if average >= 75 && difference < 15 {
            emoji = "🎉"
            message = L10n.greatPick
        } else if average >= 60 && difference < 20 {
            emoji = "👍"
            message = L10n.solidChoice
        } else if difference > 30 {
            emoji = "🤔"
            message = L10n.mightDisagree
        } else if average < 50 {
            emoji = "😬"
            message = L10n.maybeSkip
        } else {
            emoji = "👌"
            message = L10n.couldWork
        }

        return VStack(spacing: 8) {
            Text(emoji)
                .font(.system(size: 40))
            Text(message)
                .font(.headline)
            Text("\(L10n.combinedScore): \(average)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(16)
        .padding(.horizontal)
    }

    // MARK: - Data Loading

    private func loadFriends() async {
        let following = await SocialService.shared.fetchFollowing(userId: userId)
        friends = following
        isLoadingFriends = false
    }

    private func loadFriendPrediction(friend: SocialProfile) async {
        isLoadingPrediction = true
        let friendId = friend.id

        // 1. Fetch friend's scores from Supabase
        let friendScores = await ScoreService.shared.fetchScoresForUser(userId: friendId)

        // 2. Map friend scores to local movies via tmdb_id and cache as Score objects
        let allMovies = (try? context.fetch(FetchDescriptor<Movie>())) ?? []
        let moviesByTmdbID: [Int: Movie] = {
            var lookup: [Int: Movie] = [:]
            for m in allMovies {
                if let tid = m.tmdbID {
                    lookup[tid] = m
                }
            }
            return lookup
        }()

        // Check for existing cached friend scores to avoid duplicates
        let existingScores = (try? context.fetch(FetchDescriptor<Score>())) ?? []
        let existingFriendMovieIDs = Set(
            existingScores.filter { $0.ownerId == friendId.uuidString }.map { $0.movieID }
        )

        var insertedCount = 0

        for dto in friendScores {
            guard let tmdbId = dto.tmdb_id,
                  let localMovie = moviesByTmdbID[tmdbId] else { continue }

            // Check if friend has an actual score for THIS specific movie
            if localMovie.id == movie.id {
                friendActualScore = dto.display_100
            }

            // Skip if already cached locally
            if existingFriendMovieIDs.contains(localMovie.id) { continue }

            // Create local score entry for friend
            let score = Score(
                movieID: localMovie.id,
                display100: dto.display_100,
                latent: dto.latent,
                variance: dto.variance,
                ownerId: friendId.uuidString
            )
            context.insert(score)
            insertedCount += 1
        }

        if insertedCount > 0 {
            try? context.save()
        }

        // Also check by tmdb_id if we didn't match by local movie id
        if friendActualScore == nil, let thisTmdbId = movie.tmdbID {
            for dto in friendScores {
                if dto.tmdb_id == thisTmdbId {
                    friendActualScore = dto.display_100
                    break
                }
            }
        }

        // 3. Run prediction engine for friend (only if they haven't actually rated this movie)
        if friendActualScore == nil {
            let engine = LinearPredictionEngine()
            friendPrediction = engine.predict(for: movie, in: context, userId: friendId.uuidString)
        }

        isLoadingPrediction = false
        print("📊 Watch With: Loaded \(friendScores.count) friend scores, cached \(insertedCount) locally")
    }
}
