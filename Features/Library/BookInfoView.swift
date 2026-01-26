// BookInfoView.swift
// UPDATED - With Reading Tracker

import SwiftUI
import SwiftData

struct BookInfoView: View {
    @Environment(\.modelContext) private var context
    let item: TMDbItem
    
    @State private var movie: Movie? = nil
    @State private var showLogSheet = false
    @State private var showRankingSheet = false
    @State private var showSuccess = false
    @State private var userId = "guest"
    @Query private var allScores: [Score]
    @Query private var allLogs: [LogEntry]
    
    var hasRanked: Bool {
        guard let m = movie else { return false }
        return allScores.contains(where: { $0.movieID == m.id && $0.ownerId == userId })
    }
    
    var myLog: LogEntry? {
        guard let m = movie else { return nil }
        return allLogs.first(where: { $0.movie?.id == m.id && $0.ownerId == userId })
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with poster and info
                HStack(alignment: .top, spacing: 16) {
                    if let path = item.posterPath, let url = URL(string: path) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFit()
                            } else {
                                Color.gray.opacity(0.2)
                            }
                        }
                        .frame(width: 120)
                        .cornerRadius(8)
                        .shadow(radius: 5)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 120, height: 180)
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.displayTitle)
                            .font(.title3)
                            .fontWeight(.black)
                        
                        if let y = item.year {
                            Text("Published \(String(y))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Text("Book")
                            .font(.caption)
                            .bold()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .foregroundStyle(.green)
                            .cornerRadius(4)
                        
                        if let auth = item.tags?.first {
                            Text("By \(auth)")
                                .font(.caption)
                                .bold()
                        }
                    }
                }
                .padding()
                
                // READING TRACKER
                if let log = myLog {
                    ReadingTrackerCard(log: log, context: context)
                        .padding(.horizontal)
                }
                
                // Action Buttons
                HStack {
                    if hasRanked {
                        Button { handleReRank() } label: {
                            Text("Re-Rank")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    } else {
                        Button { showLogSheet = true } label: {
                            Text("Mark as Read")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    
                    Button { saveBook(as: .watchlist) } label: {
                        Text("Want to Read")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.15))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                
                // Description
                if let desc = item.overview, !desc.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.headline)
                        Text(desc)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineSpacing(4)
                    }
                    .padding()
                }
                
                Spacer()
            }
        }
        .navigationTitle("Book Details")
        .sheet(isPresented: $showLogSheet) {
            if let m = movie {
                LogSheet(movie: m, showRanking: $showRankingSheet)
            }
        }
        .sheet(isPresented: $showRankingSheet) {
            if let m = movie {
                RankingSheet(newMovie: m)
            }
        }
        .task {
            let actor = AuthService.shared.sessionActor()
            if let s = try? await actor.session() {
                userId = s.userId
            }
            if movie == nil {
                await ensureBook()
            }
        }
        .overlay(alignment: .top) {
            if showSuccess {
                SuccessToast(text: "Saved to Library")
            }
        }
    }
    
    private func ensureBook() async {
        let targetID: Int? = item.id
        let predicate = #Predicate<Movie> { $0.tmdbID == targetID }
        
        if let existing = try? context.fetch(FetchDescriptor(predicate: predicate)).first {
            self.movie = existing
        } else {
            let newBook = Movie(
                title: item.displayTitle,
                year: item.year,
                tmdbID: item.id,
                posterPath: item.posterPath,
                tags: item.tags ?? [],
                mediaType: "book",
                ownerId: userId
            )
            if let author = item.tags?.first {
                newBook.authors = [author]
            }
            context.insert(newBook)
            self.movie = newBook
        }
    }
    
    private func handleReRank() {
        guard let m = movie else { return }
        if let score = allScores.first(where: { $0.movieID == m.id && $0.ownerId == userId }) {
            context.delete(score)
            try? context.save()
        }
        showRankingSheet = true
    }
    
    private func saveBook(as state: UserItem.State) {
        guard let m = movie else { return }
        let targetID: Int? = m.tmdbID
        let itemPred = #Predicate<UserItem> { $0.movie?.tmdbID == targetID }
        
        if let existingItem = try? context.fetch(FetchDescriptor(predicate: itemPred)).first {
            existingItem.state = state
        } else {
            context.insert(UserItem(movie: m, state: state, ownerId: userId))
        }
        
        try? context.save()
        showSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showSuccess = false
        }
    }
}

// MARK: - Reading Tracker Card
struct ReadingTrackerCard: View {
    let log: LogEntry
    let context: ModelContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "book.fill")
                    .foregroundStyle(.green)
                Text("Reading Progress")
                    .font(.headline)
            }
            
            // Reading dates and buttons
            VStack(spacing: 12) {
                // Start Reading
                HStack {
                    if let startDate = log.startedReading {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Started Reading")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(startDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                        
                        Button {
                            log.startedReading = nil
                            try? context.save()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    } else {
                        Button {
                            log.startedReading = Date()
                            try? context.save()
                        } label: {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                Text("Start Reading")
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(8)
                        }
                    }
                }
                
                // Finish Reading
                HStack {
                    if let finishDate = log.finishedReading {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Finished Reading")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(finishDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                        
                        Button {
                            log.finishedReading = nil
                            try? context.save()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    } else {
                        Button {
                            log.finishedReading = Date()
                            try? context.save()
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Finish Reading")
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                        }
                        .disabled(log.startedReading == nil)
                        .opacity(log.startedReading == nil ? 0.5 : 1.0)
                    }
                }
                
                // Reading duration (if both dates exist)
                if let days = log.readingDuration, days >= 0 {
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(.purple)
                        Text("Reading time: \(days) day\(days == 1 ? "" : "s")")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
