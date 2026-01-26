// YourListView.swift
// COMPLETE VERSION - 3 tabs with sorting

import SwiftUI
import SwiftData

struct YourListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \UserItem.createdAt, order: .reverse) private var allUserItems: [UserItem]
    @State private var userId: String = "guest"
    
    // Tab selection
    enum LibraryTab: String, CaseIterable {
        case history = "History"
        case saved = "Saved"
        case lists = "Lists"
    }
    
    @State private var selectedTab: LibraryTab = .history
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom Tab Picker
                Picker("Library", selection: $selectedTab) {
                    ForEach(LibraryTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Tab Content
                Group {
                    switch selectedTab {
                    case .history:
                        WatchHistoryView()
                    case .saved:
                        SavedView()
                    case .lists:
                        CustomListsView()
                    }
                }
            }
            .navigationTitle("Library")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task {
                userId = AuthService.shared.currentUserId() ?? "guest"
            }
        }
    }
}

// MARK: - Saved View (Watchlist) - WITH SORTING + RANK ALL
struct SavedView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \UserItem.createdAt, order: .reverse) private var allUserItems: [UserItem]
    
    @State private var userId: String = "guest"
    @State private var searchText: String = ""
    @State private var sortOrder: WatchlistSortOption = .dateAdded
    @State private var showRankAll = false
    
    enum WatchlistSortOption: String, CaseIterable, Identifiable {
        case dateAdded = "Date Added"
        case predicted = "Predicted Score"
        case title = "Title"
        case year = "Year"
        
        var id: String { rawValue }
    }
    
    var watchlistItems: [UserItem] {
        allUserItems.filter {
            $0.state == .watchlist &&
            ($0.ownerId == userId || $0.ownerId == "guest") &&
            (searchText.isEmpty || $0.movie?.title.localizedCaseInsensitiveContains(searchText) == true)
        }
    }
    
    var sortedItems: [UserItem] {
        switch sortOrder {
        case .dateAdded:
            return watchlistItems.sorted { $0.createdAt > $1.createdAt }
        case .predicted:
            let engine = LinearPredictionEngine()
            return watchlistItems.sorted { (item1, item2) in
                guard let movie1 = item1.movie, let movie2 = item2.movie else { return false }
                let pred1 = engine.predict(for: movie1, in: context, userId: userId).score
                let pred2 = engine.predict(for: movie2, in: context, userId: userId).score
                return pred1 > pred2
            }
        case .title:
            return watchlistItems.sorted { ($0.movie?.title ?? "") < ($1.movie?.title ?? "") }
        case .year:
            return watchlistItems.sorted { ($0.movie?.year ?? 0) > ($1.movie?.year ?? 0) }
        }
    }
    
    // Get unranked items count for Rank All button
    var unrankedCount: Int {
        let scoreDesc = FetchDescriptor<Score>()
        let allScores = (try? context.fetch(scoreDesc)) ?? []
        let rankedMovieIDs = Set(allScores.filter { $0.ownerId == userId }.map { $0.movieID })
        
        return watchlistItems.filter { item in
            guard let movieID = item.movie?.id else { return false }
            return !rankedMovieIDs.contains(movieID)
        }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Sort Menu + Rank All button
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Sort Menu
                    Menu {
                        Picker("Sort By", selection: $sortOrder) {
                            ForEach(WatchlistSortOption.allCases) { option in
                                Label(option.rawValue, systemImage: "arrow.up.arrow.down").tag(option)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(sortOrder.rawValue)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                    }
                    
                    // Rank All button (only show if unranked items exist)
                    if unrankedCount > 0 {
                        Button {
                            showRankAll = true
                        } label: {
                            HStack {
                                Image(systemName: "star.fill")
                                Text("Rank All (\(unrankedCount))")
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(8)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            
            // List
            List {
                if sortedItems.isEmpty {
                    ContentUnavailableView(
                        "No Saved Items",
                        systemImage: "bookmark",
                        description: Text("Items you save will appear here")
                    )
                } else {
                    ForEach(sortedItems) { item in
                        if let movie = item.movie {
                            NavigationLink {
                                MovieInfoView(
                                    tmdb: createTMDbItem(from: movie),
                                    mediaType: movie.mediaType
                                )
                            } label: {
                                WatchlistRow(movie: movie, userId: userId, context: context)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    context.delete(item)
                                    try? context.save()
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .searchable(text: $searchText, prompt: "Search watchlist")
        .sheet(isPresented: $showRankAll) {
            BulkRankingView()
        }
        .task {
            userId = AuthService.shared.currentUserId() ?? "guest"
        }
    }
    
    private func createTMDbItem(from movie: Movie) -> TMDbItem {
        TMDbItem(
            id: movie.tmdbID ?? 0,
            title: movie.mediaType == "tv" ? nil : movie.title,
            name: movie.mediaType == "tv" ? movie.title : nil,
            overview: nil,
            releaseDate: movie.year.map { "\($0)-01-01" },
            firstAirDate: movie.mediaType == "tv" ? movie.year.map { "\($0)-01-01" } : nil,
            posterPath: movie.posterPath,
            genreIds: movie.genreIDs,
            tags: movie.tags,
            mediaType: movie.mediaType,
            popularity: nil
        )
    }
}

struct WatchlistRow: View {
    let movie: Movie
    let userId: String
    let context: ModelContext
    
    var prediction: PredictionExplanation? {
        let engine = LinearPredictionEngine()
        return engine.predict(for: movie, in: context, userId: userId)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            PosterThumb(posterPath: movie.posterPath, title: movie.title, width: 50)
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(movie.title)
                    .font(.headline)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    if let year = movie.year {
                        Text(String(year))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(movie.mediaType.capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                    
                    // Predicted score
                    if let pred = prediction {
                        HStack(spacing: 2) {
                            Image(systemName: "wand.and.stars")
                                .font(.caption2)
                            Text("\(Int(pred.score * 10))")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.purple)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "bookmark.fill")
                .foregroundStyle(.blue)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Custom Lists View
struct CustomListsView: View {
    var body: some View {
        List {
            ContentUnavailableView(
                "Custom Lists",
                systemImage: "list.bullet",
                description: Text("Create custom lists to organize your content")
            )
        }
        .listStyle(.plain)
    }
}

#Preview {
    YourListView()
}
