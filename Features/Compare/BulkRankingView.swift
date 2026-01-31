// BulkRankingView.swift
// IMPROVED VERSION - Fixes jump-to-start, adds shuffle, remembers position

import SwiftUI
import SwiftData

struct BulkRankingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @Query private var allUserItems: [UserItem]
    @Query private var allScores: [Score]
    @Query private var allLogs: [LogEntry]
    @Query private var allMovies: [Movie]
    
    @State private var userId: String = "guest"
    @State private var unrankedItems: [Movie] = []
    @State private var currentIndex: Int = 0
    @State private var isLoading: Bool = true
    @State private var showRankingSheet: Bool = false
    @State private var mediaFilter: String = "All"
    @State private var isShuffled: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView("Loading unranked items...")
                } else if unrankedItems.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)
                        
                        Text("All Caught Up!")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("You've ranked everything you've watched")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    // Progress indicator
                    VStack(spacing: 8) {
                        HStack {
                            Text("Progress")
                                .font(.headline)
                            Spacer()
                            Text("\(currentIndex + 1) of \(unrankedItems.count)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        ProgressView(value: Double(currentIndex + 1), total: Double(unrankedItems.count))
                            .tint(.green)
                    }
                    .padding()
                    
                    // Media Filter + Shuffle
                    VStack(spacing: 10) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                FilterPill("All", tag: "All")
                                FilterPill("Movies", tag: "movie")
                                FilterPill("TV", tag: "tv")
                                FilterPill("Books", tag: "book")
                                FilterPill("Podcasts", tag: "podcast")
                            }
                            .padding(.horizontal)
                        }
                        
                        // Shuffle Button
                        Button {
                            shuffleItems()
                        } label: {
                            HStack {
                                Image(systemName: "shuffle")
                                Text(isShuffled ? "Shuffled" : "Shuffle Order")
                            }
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isShuffled ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                            .foregroundStyle(isShuffled ? .green : .secondary)
                            .cornerRadius(20)
                        }
                    }
                    
                    // Current movie to rank
                    if currentIndex < unrankedItems.count {
                        let movie = unrankedItems[currentIndex]
                        
                        VStack(spacing: 20) {
                            PosterThumb(posterPath: movie.posterPath, title: movie.title, width: 200)
                                .shadow(radius: 10)
                            
                            VStack(spacing: 8) {
                                Text(movie.title)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)
                                
                                if let year = movie.year {
                                    Text(String(year))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal)
                            
                            // Action buttons
                            VStack(spacing: 12) {
                                Button {
                                    showRankingSheet = true
                                } label: {
                                    Label("Rank This", systemImage: "chart.bar.fill")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.accentColor)
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                }
                                
                                Button {
                                    skipCurrent()
                                } label: {
                                    Text("Skip for Now")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 40)
                        }
                        .padding()
                    }
                    
                    Spacer()
                }
            }
            .navigationTitle("Rank Unranked")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                userId = AuthService.shared.currentUserId() ?? "guest"
                loadUnrankedItems()
            }
            .onChange(of: mediaFilter) { _, _ in
                loadUnrankedItems()
            }
            .sheet(isPresented: $showRankingSheet, onDismiss: {
                // After ranking, move to NEXT item instead of reloading
                handlePostRanking()
            }) {
                if currentIndex < unrankedItems.count {
                    RankingSheet(newMovie: unrankedItems[currentIndex])
                }
            }
        }
    }
    
    func FilterPill(_ label: String, tag: String) -> some View {
        Button { mediaFilter = tag } label: {
            Text(label).font(.subheadline).bold()
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(mediaFilter == tag ? Color.accentColor : Color.gray.opacity(0.1))
                .foregroundColor(mediaFilter == tag ? .white : .primary)
                .cornerRadius(20)
        }
    }
    
    private func skipCurrent() {
        if currentIndex < unrankedItems.count - 1 {
            currentIndex += 1
        } else {
            // Reached end, reload
            loadUnrankedItems()
        }
    }
    
    private func handlePostRanking() {
        // Remove the ranked item from the list
        if currentIndex < unrankedItems.count {
            unrankedItems.remove(at: currentIndex)
        }
        
        // If we removed the last item, go back one
        if currentIndex >= unrankedItems.count && currentIndex > 0 {
            currentIndex -= 1
        }
        
        // If list is empty, reload
        if unrankedItems.isEmpty {
            loadUnrankedItems()
        }
    }
    
    private func shuffleItems() {
        // Save current movie if possible
        let currentMovie = currentIndex < unrankedItems.count ? unrankedItems[currentIndex] : nil
        
        // Shuffle
        unrankedItems.shuffle()
        isShuffled = true
        
        // Try to find the current movie in the new order
        if let movie = currentMovie, let newIndex = unrankedItems.firstIndex(where: { $0.id == movie.id }) {
            currentIndex = newIndex
        } else {
            currentIndex = 0
        }
    }
    
    private func loadUnrankedItems() {
        print("\n🔍 BULK RANKING - Loading unranked items...")
        print("👤 User: \(userId)")
        
        // Filter Logs in memory (use logs to avoid ranking duplicates)
        let seenLogs = allLogs.filter { log in
            (log.ownerId == userId || log.ownerId == "guest") && log.movie != nil
        }
        
        print("📊 Total UserItems: \(allUserItems.count)")
        print("📊 Total Logs: \(allLogs.count)")
        print("📊 Seen logs for user: \(seenLogs.count)")
        
        // Filter Scores in memory
        let userScores = allScores.filter { score in
            score.ownerId == userId || score.ownerId == "guest"
        }
        
        let rankedMovieIDs = Set(userScores.map { $0.movieID })
        
        print("📊 Total Scores: \(allScores.count)")
        print("📊 User scores: \(userScores.count)")
        print("📊 Ranked movie IDs: \(rankedMovieIDs.count)")
        
        // Find unranked movies
        var unranked: [Movie] = []
        var seenKeys = Set<String>()
        
        for log in seenLogs {
            guard let movie = resolveMovie(from: log.movie) else { continue }
            let isRanked = rankedMovieIDs.contains(movie.id)
            if isRanked { continue }
            
            // Apply media filter
            if mediaFilter != "All" && movie.mediaType != mediaFilter {
                continue
            }
            
            let dedupeKey: String
            if let tmdbID = movie.tmdbID {
                dedupeKey = "tmdb:\(tmdbID)"
            } else {
                dedupeKey = "title:\(movie.titleLower)"
            }
            
            if seenKeys.contains(dedupeKey) {
                continue
            }
            
            seenKeys.insert(dedupeKey)
            unranked.append(movie)
        }
        
        print("📊 Unranked items found: \(unranked.count)")
        
        // Sort by title (alphabetical) - user can shuffle if they want
        unranked.sort { $0.title < $1.title }
        
        self.unrankedItems = unranked
        self.currentIndex = 0
        self.isLoading = false
        self.isShuffled = false
        
        print("✅ Loading complete\n")
    }

    private func resolveMovie(from movie: Movie?) -> Movie? {
        guard let movie else { return nil }
        if let tmdbID = movie.tmdbID {
            for candidate in allMovies where candidate.tmdbID == tmdbID {
                return candidate
            }
        }
        let normalizedTitle = movie.titleLower
        for candidate in allMovies {
            if candidate.titleLower != normalizedTitle { continue }
            if candidate.mediaType != movie.mediaType { continue }
            if let candidateYear = candidate.year, let movieYear = movie.year, candidateYear != movieYear { continue }
            if candidate.tmdbID == nil { continue }
            return candidate
        }
        return movie
    }
}

#Preview {
    BulkRankingView()
}
