// WatchHistoryView.swift
// WITH SORTING - Like Leaderboard style

import SwiftUI
import SwiftData

struct WatchHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query private var logs: [LogEntry]
    @Query private var scores: [Score]
    
    @State private var userId: String = "guest"
    @State private var searchText: String = ""
    @State private var sortOrder: HistorySortOption = .dateWatched
    
    enum HistorySortOption: String, CaseIterable, Identifiable {
        case dateWatched = "Date Watched"
        case score = "Your Score"
        case title = "Title"
        case year = "Year"
        
        var id: String { rawValue }
    }
    
    var filteredLogs: [LogEntry] {
        let filtered = logs.filter { log in
            (log.ownerId == userId || log.ownerId == "guest") &&
            (searchText.isEmpty || log.movie?.title.localizedCaseInsensitiveContains(searchText) == true)
        }
        
        // Sort based on selection
        switch sortOrder {
        case .dateWatched:
            return filtered.sorted { ($0.watchedOn ?? Date.distantPast) > ($1.watchedOn ?? Date.distantPast) }
        case .score:
            return filtered.sorted { (log1, log2) in
                let score1 = scores.first { $0.movieID == log1.movie?.id && $0.ownerId == userId }?.display100 ?? 0
                let score2 = scores.first { $0.movieID == log2.movie?.id && $0.ownerId == userId }?.display100 ?? 0
                return score1 > score2
            }
        case .title:
            return filtered.sorted { ($0.movie?.title ?? "") < ($1.movie?.title ?? "") }
        case .year:
            return filtered.sorted { ($0.movie?.year ?? 0) > ($1.movie?.year ?? 0) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Sort Menu
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Menu {
                        Picker("Sort By", selection: $sortOrder) {
                            ForEach(HistorySortOption.allCases) { option in
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
                    
                    Spacer()
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            
            // List
            List {
                ForEach(filteredLogs) { log in
                    if let movie = log.movie {
                        NavigationLink {
                            MovieInfoView(tmdb: TMDbItem(
                                id: movie.tmdbID ?? 0,
                                title: movie.mediaType == "tv" ? nil : movie.title,
                                name: movie.mediaType == "tv" ? movie.title : nil,
                                overview: nil,
                                releaseDate: movie.year.map { "\($0)-01-01" },
                                firstAirDate: movie.mediaType == "tv" ? movie.year.map { "\($0)-01-01" } : nil,
                                posterPath: movie.posterPath,
                                genreIds: movie.genreIDs,
                                mediaType: movie.mediaType
                            ), mediaType: movie.mediaType)
                        } label: {
                            HStack(spacing: 12) {
                                PosterThumb(posterPath: movie.posterPath, title: movie.title, width: 50)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(movie.title)
                                        .font(.headline)
                                    
                                    HStack(spacing: 8) {
                                        if let date = log.watchedOn {
                                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        if let year = movie.year {
                                            Text("(\(year))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                if let score = scores.first(where: { $0.movieID == movie.id && $0.ownerId == userId }) {
                                    Text("\(score.display100)")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Watch History")
        .searchable(text: $searchText)
        .task {
            userId = AuthService.shared.currentUserId() ?? "guest"
        }
    }
}
