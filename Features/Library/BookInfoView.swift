// BookInfoView.swift
// UPDATED - With 3-Button Reading Flow

import SwiftUI
import SwiftData

struct BookInfoView: View {
    @Environment(\.modelContext) private var context
    let item: TMDbItem

    @State private var movie: Movie? = nil
    @State private var showLogSheet = false
    @State private var showRankingSheet = false
    @State private var showStartedSheet = false
    @State private var showSuccess = false
    @State private var successMessage = "Saved to Library"
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

    var isCurrentlyReading: Bool {
        guard let log = myLog else { return false }
        return log.startedReading != nil && log.finishedReading == nil
    }

    var hasFinishedReading: Bool {
        guard let log = myLog else { return false }
        return log.finishedReading != nil
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
                
                // Action Buttons - 3 Button Flow
                VStack(spacing: 12) {
                    // Row 1: Started Reading / Currently Reading status
                    if isCurrentlyReading {
                        // Currently reading - show status and finish button
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Currently Reading")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let start = myLog?.startedReading {
                                    Text("Started \(start.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(12)

                            Button { showLogSheet = true } label: {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Finished")
                                }
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                        }
                    } else if hasFinishedReading || hasRanked {
                        // Already finished - show re-rank option
                        Button { handleReRank() } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Re-Rank This Book")
                            }
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    } else {
                        // Not started yet - show all 3 options
                        HStack(spacing: 12) {
                            Button { showStartedSheet = true } label: {
                                HStack {
                                    Image(systemName: "book.fill")
                                    Text("Started")
                                }
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }

                            Button { showLogSheet = true } label: {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Finished")
                                }
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                        }

                        Button { saveBook(as: .watchlist) } label: {
                            HStack {
                                Image(systemName: "bookmark.fill")
                                Text("Want to Read")
                            }
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.15))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                        }
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
        .sheet(isPresented: $showStartedSheet) {
            if let m = movie {
                StartedReadingSheet(movie: m, userId: userId, onSave: { date in
                    startReading(on: date)
                    showStartedSheet = false
                })
            }
        }
        .sheet(isPresented: $showLogSheet) {
            if let m = movie {
                LogSheet(movie: m, existingLog: myLog, showRanking: $showRankingSheet)
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
                SuccessToast(text: successMessage)
            }
        }
    }
    
    private func ensureBook() async {
        let targetID = item.id
        let allMovies = (try? context.fetch(FetchDescriptor<Movie>())) ?? []

        if let existing = allMovies.first(where: { $0.tmdbID == targetID }) {
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
        let targetID = m.tmdbID
        let allItems = (try? context.fetch(FetchDescriptor<UserItem>())) ?? []

        if let existingItem = allItems.first(where: { $0.movie?.tmdbID == targetID }) {
            existingItem.state = state
        } else {
            context.insert(UserItem(movie: m, state: state, ownerId: userId))
        }

        try? context.save()
        successMessage = "Added to Want to Read"
        showSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showSuccess = false
        }
    }

    private func startReading(on date: Date) {
        guard let m = movie else { return }

        // Check if log already exists, update it; otherwise create new
        if let existingLog = myLog {
            existingLog.startedReading = date
            existingLog.finishedReading = nil  // Reset finished if re-starting
        } else {
            let newLog = LogEntry(
                createdAt: Date(),
                watchedOn: nil,
                movie: m,
                ownerId: userId,
                startedReading: date,
                finishedReading: nil
            )
            context.insert(newLog)
        }

        try? context.save()
        successMessage = "Started Reading!"
        showSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showSuccess = false
        }
    }
}

// MARK: - Started Reading Sheet with Calendar
struct StartedReadingSheet: View {
    let movie: Movie
    let userId: String
    let onSave: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Book info header
                HStack(spacing: 12) {
                    if let path = movie.posterPath, let url = URL(string: path) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFit()
                            } else {
                                Color.gray.opacity(0.2)
                            }
                        }
                        .frame(width: 60, height: 90)
                        .cornerRadius(6)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(movie.title)
                            .font(.headline)
                            .lineLimit(2)
                        if let author = movie.authors?.first {
                            Text("by \(author)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Date picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("When did you start reading?")
                        .font(.headline)

                    DatePicker(
                        "Start Date",
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }

                Spacer()

                // Save button
                Button {
                    onSave(selectedDate)
                } label: {
                    Text("Start Reading")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding()
            .navigationTitle("Started Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
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
