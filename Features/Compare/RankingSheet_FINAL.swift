// RankingSheet.swift
// COMPLETE FILE - Full cloud sync + improved algorithm

import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct RankingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let newMovie: Movie
    
    // State for the ranking logic
    @State private var relevantScores: [Score] = []
    @State private var lowerBound: Int = 0
    @State private var upperBound: Int = 0
    @State private var currentIndex: Int = 0
    @State private var battleOpponent: Movie? = nil
    @State private var userId: String = "guest"
    
    // UI State
    enum Stage { case sentiment, battle }
    @State private var stage: Stage = .sentiment
    
    enum SentimentTier { case high, mid, low }
    
    var body: some View {
        NavigationStack {
            VStack {
                if stage == .sentiment {
                    sentimentView
                        .transition(.opacity)
                } else {
                    battleView
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                }
            }
            .navigationTitle(stage == .sentiment ? "How was it?" : "Rank It")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .interactiveDismissDisabled()
            .toolbar {
                if stage == .battle {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .task {
                userId = AuthService.shared.currentUserId() ?? "guest"
                await prepareBattle()
            }
        }
    }
    
    // MARK: - Logic Setup
    
    private func prepareBattle() async {
        let descriptor = FetchDescriptor<Score>(sortBy: [SortDescriptor(\.display100, order: .reverse)])

        do {
            let allScores = try context.fetch(descriptor)
            let myScores = allScores.filter { $0.ownerId == userId || $0.ownerId == "guest" }

            // Fetch all movies once for efficiency
            let allMovies = (try? context.fetch(FetchDescriptor<Movie>())) ?? []

            var sameTypeScores: [Score] = []

            for score in myScores {
                if score.movieID == newMovie.id { continue }

                if let m = allMovies.first(where: { $0.id == score.movieID }) {
                    if m.mediaType == newMovie.mediaType {
                        sameTypeScores.append(score)
                    }
                }
            }
            
            await MainActor.run {
                self.relevantScores = sameTypeScores
            }
        } catch {
            print("Error fetching scores: \(error)")
        }
    }
    
    // MARK: - Haptic Helper
    private func triggerHaptic(heavy: Bool = false) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: heavy ? .heavy : .medium)
        generator.impactOccurred()
        #endif
    }
    
    // MARK: - Stage 1: Sentiment
    
    var sentimentView: some View {
        VStack(spacing: 40) {
            Spacer()
            
            PosterThumb(posterPath: newMovie.posterPath, title: newMovie.title, width: 140)
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            
            VStack(spacing: 8) {
                Text(newMovie.title)
                    .font(.title2).fontWeight(.black)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                if let y = newMovie.year {
                    Text(String(y)).foregroundStyle(.secondary)
                }
            }
            
            if relevantScores.isEmpty {
                Button {
                    triggerHaptic(heavy: true)
                    saveSingleScore(85)
                } label: {
                    Text("My First Log!")
                        .font(.headline).bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 40)
            } else {
                HStack(spacing: 16) {
                    SentimentButton(color: .green, icon: "arrow.up.heart.fill", label: "Loved it") {
                        configureBattle(tier: .high)
                    }
                    SentimentButton(color: .blue, icon: "hand.thumbsup.fill", label: "Liked it") {
                        configureBattle(tier: .mid)
                    }
                    SentimentButton(color: .gray, icon: "hand.thumbsdown.fill", label: "Meh") {
                        configureBattle(tier: .low)
                    }
                }
                .padding(.horizontal)
            }
            
            Spacer()
        }
    }
    
    private func configureBattle(tier: SentimentTier) {
        triggerHaptic(heavy: false)
        
        let total = relevantScores.count
        guard total > 0 else { saveSingleScore(85); return }
        
        if total < 5 {
            lowerBound = 0; upperBound = total - 1
        } else {
            switch tier {
            case .high:
                lowerBound = 0
                upperBound = Int(Double(total) * 0.35)
            case .mid:
                lowerBound = Int(Double(total) * 0.30)
                upperBound = Int(Double(total) * 0.70)
            case .low:
                lowerBound = Int(Double(total) * 0.65)
                upperBound = total - 1
            }
        }
        
        lowerBound = max(0, lowerBound)
        upperBound = min(total - 1, upperBound)
        
        if lowerBound > upperBound {
            lowerBound = 0; upperBound = total - 1
        }
        
        withAnimation {
            stage = .battle
            pickNextOpponent()
        }
    }
    
    // MARK: - Stage 2: The Battle
    
    var battleView: some View {
        ZStack {
            if let opponent = battleOpponent {
                VStack(spacing: 20) {
                    
                    Text("Which is better?")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(2)
                        .padding(.top)
                    
                    Spacer()
                    
                    VStack(spacing: 0) {
                        BattleCard(movie: newMovie, color: .blue)
                            .onTapGesture { userChose(newMovieIsBetter: true) }
                        
                        ZStack {
                            Circle().fill(Color.white).frame(width: 50, height: 50)
                                .shadow(radius: 5)
                            Text("VS").font(.headline).fontWeight(.black).italic()
                        }
                        .zIndex(10)
                        .offset(y: 0)
                        
                        BattleCard(movie: opponent, color: .purple)
                            .onTapGesture { userChose(newMovieIsBetter: false) }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    Button {
                        finalizeRank(at: currentIndex, tie: true)
                    } label: {
                        Text("I can't decide (Tie)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
            } else {
                ProgressView()
            }
        }
    }
    
    // MARK: - Algorithm
    
    private func pickNextOpponent() {
        if lowerBound > upperBound {
            finalizeRank(at: lowerBound, tie: false)
            return
        }
        
        currentIndex = (lowerBound + upperBound) / 2
        
        guard relevantScores.indices.contains(currentIndex) else {
            finalizeRank(at: lowerBound, tie: false)
            return
        }
        
        let opponentScore = relevantScores[currentIndex]

        let targetID = opponentScore.movieID
        let allMovies = (try? context.fetch(FetchDescriptor<Movie>())) ?? []

        if let opponent = allMovies.first(where: { $0.id == targetID }) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                battleOpponent = opponent
            }
        } else {
            finalizeRank(at: lowerBound, tie: false)
        }
    }
    
    private func userChose(newMovieIsBetter: Bool) {
        triggerHaptic(heavy: false)
        
        if newMovieIsBetter {
            upperBound = currentIndex - 1
        } else {
            lowerBound = currentIndex + 1
        }
        
        pickNextOpponent()
    }
    
    private func saveSingleScore(_ val: Int) {
        let newScore = Score(movieID: newMovie.id, display100: val, latent: 0, variance: 0, ownerId: userId)
        context.insert(newScore)
        markMovieAsSeen()
        try? context.save()
        uploadToCloud(score: newScore)
        dismiss()
    }
    
    // IMPROVED ALGORITHM - Natural spread!
    private func finalizeRank(at insertIndex: Int, tie: Bool) {
        triggerHaptic(heavy: true)
        
        var calculatedScore: Int
        
        if relevantScores.isEmpty {
            calculatedScore = 85
        } else if tie && relevantScores.indices.contains(currentIndex) {
            calculatedScore = relevantScores[currentIndex].display100
        } else if insertIndex == 0 {
            let currentBest = relevantScores.first?.display100 ?? 85
            let gap = min(8, (99 - currentBest) / 2)
            calculatedScore = min(currentBest + gap, 99)
        } else if insertIndex >= relevantScores.count {
            let currentWorst = relevantScores.last?.display100 ?? 50
            let gap = min(8, (currentWorst - 1) / 2)
            calculatedScore = max(currentWorst - gap, 1)
        } else {
            let aboveScore = relevantScores[insertIndex - 1].display100
            let belowScore = relevantScores[insertIndex].display100
            
            let gap = aboveScore - belowScore
            
            if gap <= 1 {
                calculatedScore = belowScore
            } else if gap == 2 {
                calculatedScore = belowScore + 1
            } else {
                calculatedScore = (aboveScore + belowScore) / 2
            }
        }
        
        let newScore = Score(
            movieID: newMovie.id,
            display100: calculatedScore,
            latent: 0,
            variance: 0,
            ownerId: userId
        )
        context.insert(newScore)
        
        markMovieAsSeen()
        try? context.save()
        uploadToCloud(score: newScore)
        dismiss()
    }
    
    // MARK: - Update UserItem for Profile Stats
    private func markMovieAsSeen() {
        let targetID = newMovie.id
        let allItems = (try? context.fetch(FetchDescriptor<UserItem>())) ?? []

        if let existing = allItems.first(where: { $0.movie?.id == targetID }) {
            existing.ownerId = userId
            existing.state = .seen
        } else {
            context.insert(UserItem(movie: newMovie, state: .seen, ownerId: userId))
        }
    }

    // 🆕 FULL CLOUD SYNC - Uploads EVERYTHING!
    private func uploadToCloud(score: Score) {
        let targetID = newMovie.id
        let allLogs = (try? context.fetch(FetchDescriptor<LogEntry>())) ?? []
        let log = allLogs.filter { $0.movie?.id == targetID }.last

        Task {
            let date = log?.watchedOn ?? Date()

            // 1. Upload log (activity feed)
            await FeedService.shared.uploadLog(
                movie: newMovie,
                score: score.display100,
                notes: log?.notes,
                platform: log?.whereWatched?.rawValue,
                date: date
            )
            print("✅ Uploaded log for \(newMovie.title)")

            // 2. Upload score (the actual rating!)
            await ScoreService.shared.uploadScore(score, movie: newMovie)
            print("✅ Uploaded score for \(newMovie.title): \(score.display100)")

            // 3. Upload UserItem (seen status)
            let allItems = (try? context.fetch(FetchDescriptor<UserItem>())) ?? []
            if let item = allItems.first(where: { $0.movie?.id == targetID }) {
                await UserItemService.shared.uploadUserItem(item, movie: newMovie)
                print("✅ Uploaded seen status for \(newMovie.title)")
            }
        }
    }
}

// MARK: - Subviews

struct SentimentButton: View {
    let color: Color
    let icon: String
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: icon)
                        .font(.system(size: 32))
                        .foregroundStyle(color)
                }
                
                Text(label)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct BattleCard: View {
    let movie: Movie
    let color: Color
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                #if os(iOS)
                .fill(Color(uiColor: .systemBackground))
                #else
                .fill(Color.gray.opacity(0.1))
                #endif
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
            
            RoundedRectangle(cornerRadius: 20)
                .stroke(color.opacity(0.3), lineWidth: 1)
            
            HStack(spacing: 16) {
                PosterThumb(posterPath: movie.posterPath, title: movie.title, width: 70)
                    .shadow(radius: 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(movie.title)
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                    
                    if let y = movie.year {
                        Text(String(y))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary.opacity(0.5))
            }
            .padding()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
