// WatchHistoryView.swift
// WITH SORTING + EDIT FUNCTIONALITY

import SwiftUI
import SwiftData

struct WatchHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query private var logs: [LogEntry]
    @Query private var scores: [Score]

    @State private var userId: String = "guest"
    @State private var searchText: String = ""
    @State private var editingLog: LogEntry? = nil
    @AppStorage("historySortOrder") private var sortOrderRaw: String = HistorySortOption.dateWatched.rawValue
    @AppStorage("historySortAscending") private var sortAscending: Bool = false // false = descending (newest first)

    var sortOrder: HistorySortOption {
        HistorySortOption(rawValue: sortOrderRaw) ?? .dateWatched
    }

    func setSortOrder(_ newValue: HistorySortOption) {
        sortOrderRaw = newValue.rawValue
    }

    enum HistorySortOption: String, CaseIterable, Identifiable {
        case dateWatched = "Date Watched"
        case score = "Your Score"
        case title = "Title"
        case year = "Year"

        var id: String { rawValue }
    }

    // Precomputed score lookup dictionary for O(1) access (fixes N+1 query issue)
    var scoreLookup: [UUID: Int] {
        var lookup: [UUID: Int] = [:]
        for score in scores where score.ownerId == userId {
            lookup[score.movieID] = score.display100
        }
        return lookup
    }

    var filteredLogs: [LogEntry] {
        let filtered = logs.filter { log in
            (log.ownerId == userId || log.ownerId == "guest") &&
            (searchText.isEmpty || log.movie?.title.localizedCaseInsensitiveContains(searchText) == true)
        }

        // Deduplicate: keep only the most recent log per movie
        var seenMovieIds = Set<UUID>()
        let sortedByDate = filtered.sorted { ($0.watchedOn ?? .distantPast) > ($1.watchedOn ?? .distantPast) }
        let deduped = sortedByDate.filter { log in
            guard let movieId = log.movie?.id else { return true }
            return seenMovieIds.insert(movieId).inserted
        }

        // Use precomputed lookup for O(1) score access
        let lookup = scoreLookup
        let filtered2 = deduped

        // Sort based on selection (with ascending/descending support)
        let sorted: [LogEntry]
        switch sortOrder {
        case .dateWatched:
            sorted = filtered2.sorted { ($0.watchedOn ?? Date.distantPast) > ($1.watchedOn ?? Date.distantPast) }
        case .score:
            sorted = filtered2.sorted { (log1, log2) in
                let score1 = log1.movie.flatMap { lookup[$0.id] } ?? 0
                let score2 = log2.movie.flatMap { lookup[$0.id] } ?? 0
                return score1 > score2
            }
        case .title:
            sorted = filtered2.sorted { ($0.movie?.title ?? "") < ($1.movie?.title ?? "") }
        case .year:
            sorted = filtered2.sorted { ($0.movie?.year ?? 0) > ($1.movie?.year ?? 0) }
        }
        return sortAscending ? sorted.reversed() : sorted
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Sort Menu
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Menu {
                        Picker("Sort By", selection: Binding(
                            get: { sortOrder },
                            set: { setSortOrder($0) }
                        )) {
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

                    // Ascending/Descending Toggle
                    Button {
                        sortAscending.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                            Text(sortAscending ? "Ascending" : "Descending")
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.15))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                    }

                    Spacer()
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            
            // List
            List {
                // Capture scoreLookup once for the list to avoid recomputation per row
                let lookup = scoreLookup
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

                                // Use O(1) dictionary lookup instead of O(n) linear search
                                if let scoreValue = lookup[movie.id] {
                                    Text("\(scoreValue)")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteLogEntry(log, movie: movie)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                editingLog = log
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .searchable(text: $searchText)
        .task {
            userId = AuthService.shared.currentUserId() ?? "guest"
        }
        .sheet(item: $editingLog) { log in
            EditEntrySheet(log: log, context: context)
        }
    }

    private func deleteLogEntry(_ log: LogEntry, movie: Movie) {
        // Delete the log entry
        context.delete(log)

        // Also delete any associated score for this movie
        if let score = scores.first(where: { $0.movieID == movie.id && $0.ownerId == userId }) {
            context.delete(score)
        }

        // Also delete any UserItem marking this as seen
        let allUserItems = (try? context.fetch(FetchDescriptor<UserItem>())) ?? []
        if let userItem = allUserItems.first(where: { $0.movie?.id == movie.id && $0.ownerId == userId && $0.state == .seen }) {
            context.delete(userItem)
        }

        try? context.save()
    }
}

// MARK: - Edit Entry Sheet
struct EditEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let log: LogEntry
    let context: ModelContext

    @State private var watchedOn: Date
    @State private var platform: String
    @State private var withWho: String
    @State private var notes: String
    @State private var showDatePicker = false

    let visualPlatforms = ["Theater", "Netflix", "HBO/Max", "Hulu", "Prime Video", "Apple TV+", "Disney+", "Other", "Not Sure"]
    let audioPlatforms = ["Apple Podcasts", "Spotify", "YouTube", "Overcast", "Pocket Casts", "Other", "Not Sure"]

    var isBook: Bool { log.movie?.mediaType == "book" }
    var isPodcast: Bool { log.movie?.mediaType == "podcast" }

    init(log: LogEntry, context: ModelContext) {
        self.log = log
        self.context = context
        _watchedOn = State(initialValue: log.watchedOn ?? Date())
        _platform = State(initialValue: log.whereWatched?.rawValue.capitalized ?? "Other")
        _withWho = State(initialValue: log.withWho ?? "")
        _notes = State(initialValue: log.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                // Movie/Book Info Header
                if let movie = log.movie {
                    Section {
                        HStack(spacing: 12) {
                            PosterThumb(posterPath: movie.posterPath, title: movie.title, width: 50)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(movie.title)
                                    .font(.headline)
                                if let year = movie.year {
                                    Text(String(year))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // Date Section
                Section("When") {
                    DatePicker(
                        isBook ? "Date Read" : "Date Watched",
                        selection: $watchedOn,
                        displayedComponents: .date
                    )

                    if log.watchedOn != nil {
                        Button(role: .destructive) {
                            log.watchedOn = nil
                        } label: {
                            Text("Clear Date")
                                .font(.caption)
                        }
                    }
                }

                // Platform Section (not for books)
                if !isBook {
                    Section("Platform") {
                        Picker("Watched On", selection: $platform) {
                            ForEach(isPodcast ? audioPlatforms : visualPlatforms, id: \.self) { p in
                                Text(p).tag(p)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                // Watched With Section
                Section("Watched With") {
                    TextField(isBook ? "Read with..." : "Watched with...", text: $withWho)
                }

                // Notes Section
                Section("Notes") {
                    TextField("Your thoughts...", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Edit Entry")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .bold()
                }
            }
        }
    }

    private func saveChanges() {
        // Update the log entry - always save the date from the DatePicker
        log.watchedOn = watchedOn

        // Map platform string to WatchLocation
        if !isBook {
            switch platform.lowercased() {
            case "theater": log.whereWatched = .theater
            case "not sure": log.whereWatched = .notSure
            default: log.whereWatched = .other
            }
        }

        log.withWho = withWho.isEmpty ? nil : withWho
        log.notes = notes.isEmpty ? nil : notes

        try? context.save()
        dismiss()
    }
}
