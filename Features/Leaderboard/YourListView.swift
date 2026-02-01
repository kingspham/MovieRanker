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
    @Query private var allScores: [Score]

    @State private var userId: String = "guest"
    @State private var searchText: String = ""
    @AppStorage("watchlistSortOrder") private var sortOrderRaw: String = WatchlistSortOption.dateAdded.rawValue
    @AppStorage("watchlistSortAscending") private var sortAscending: Bool = false // false = descending
    @State private var showRankAll = false

    // Cached predictions to avoid recomputing on every render
    @State private var predictionCache: [UUID: Double] = [:]
    @State private var isPredictionsLoaded = false
    @State private var cachedUnrankedCount: Int = 0

    var sortOrder: WatchlistSortOption {
        get { WatchlistSortOption(rawValue: sortOrderRaw) ?? .dateAdded }
    }

    func setSortOrder(_ newValue: WatchlistSortOption) {
        sortOrderRaw = newValue.rawValue
    }

    enum WatchlistSortOption: String, CaseIterable, Identifiable {
        case dateAdded = "Date Added"
        case predicted = "Predicted Score"
        case title = "Title"
        case year = "Year"
        case metacritic = "Metacritic"
        case imdb = "IMDb"
        case rottenTomatoes = "Rotten Tomatoes"

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
        let items = watchlistItems
        let sorted: [UserItem]
        switch sortOrder {
        case .dateAdded:
            sorted = items.sorted { $0.createdAt > $1.createdAt }
        case .predicted:
            // Use cached predictions for sorting
            sorted = watchlistItems.sorted { (item1, item2) in
                let pred1 = predictionCache[item1.movie?.id ?? item1.id] ?? 50.0
                let pred2 = predictionCache[item2.movie?.id ?? item2.id] ?? 50.0
                return pred1 > pred2
            }
        case .title:
            sorted = items.sorted { ($0.movie?.title ?? "") < ($1.movie?.title ?? "") }
        case .year:
            sorted = items.sorted { ($0.movie?.year ?? 0) > ($1.movie?.year ?? 0) }
        case .metacritic:
            sorted = items.sorted { metaScore(for: $0) > metaScore(for: $1) }
        case .imdb:
            sorted = items.sorted { imdbScore(for: $0) > imdbScore(for: $1) }
        case .rottenTomatoes:
            sorted = items.sorted { rottenTomatoesScore(for: $0) > rottenTomatoesScore(for: $1) }
        }
        return sortAscending ? sorted.reversed() : sorted
    }

    // Compute unranked count from cached data (not a computed property to avoid repeated fetches)
    private func updateUnrankedCount() {
        let rankedMovieIDs = Set(allScores.filter { $0.ownerId == userId }.map { $0.movieID })
        cachedUnrankedCount = watchlistItems.filter { item in
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
                        Picker("Sort By", selection: Binding(
                            get: { sortOrder },
                            set: { setSortOrder($0) }
                        )) {
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

                    // Rank All button (only show if unranked items exist)
                    if cachedUnrankedCount > 0 {
                        Button {
                            showRankAll = true
                        } label: {
                            HStack {
                                Image(systemName: "star.fill")
                                Text("Rank All (\(cachedUnrankedCount))")
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
                                WatchlistRow(
                                    movie: movie,
                                    userId: userId,
                                    cachedPredictionScore: predictionCache[movie.id]
                                )
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
            updateUnrankedCount()
            // Only pre-load predictions if sort is set to predicted
            if sortOrder == .predicted {
                await loadPredictions()
            }
        }
        .onChange(of: sortOrder) { _, newValue in
            if newValue == .predicted && !isPredictionsLoaded {
                Task { await loadPredictions() }
            }
        }
        .onChange(of: allUserItems.count) { _, _ in
            // Update unranked count when items change
            updateUnrankedCount()
        }
    }

    private func loadPredictions() async {
        guard !isPredictionsLoaded else { return }

        // Get all movies from watchlist
        let movies = watchlistItems.compactMap { $0.movie }
        guard !movies.isEmpty else {
            isPredictionsLoaded = true
            return
        }

        let engine = LinearPredictionEngine()
        var newCache: [UUID: Double] = [:]
        for movie in movies {
            let pred = engine.predict(for: movie, in: context, userId: userId)
            let score100 = pred.score * 10.0
            newCache[movie.id] = score100
            print("📊 Prediction for \(movie.title): \(Int(score100))")
        }

        await MainActor.run {
            predictionCache = newCache
            isPredictionsLoaded = true
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
    
    private func metaScore(for item: UserItem) -> Int {
        Int(item.movie?.metaScore ?? "0") ?? 0
    }
    
    private func imdbScore(for item: UserItem) -> Double {
        Double(item.movie?.imdbRating ?? "0") ?? 0
    }
    
    private func rottenTomatoesScore(for item: UserItem) -> Int {
        let value = item.movie?.rottenTomatoesRating ?? "0"
        return Int(value.replacingOccurrences(of: "%", with: "")) ?? 0
    }
}

struct WatchlistRow: View {
    let movie: Movie
    let userId: String
    // Cached prediction score passed from parent (avoids recomputing on every render)
    var cachedPredictionScore: Double?

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

                    // Predicted score (uses cached value from parent)
                    if let predScore = cachedPredictionScore {
                        HStack(spacing: 2) {
                            Image(systemName: "wand.and.stars")
                                .font(.caption2)
                            Text("\(Int(predScore))")
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
    @Environment(\.modelContext) private var context
    @Query(sort: \CustomList.createdAt, order: .reverse) private var allLists: [CustomList]
    @State private var userId: String = "guest"
    @State private var showCreateSheet = false

    var myLists: [CustomList] {
        allLists.filter { $0.ownerId == userId || $0.ownerId == "guest" }
    }

    var body: some View {
        List {
            if myLists.isEmpty {
                ContentUnavailableView(
                    "No Lists Yet",
                    systemImage: "list.bullet",
                    description: Text("Create custom lists to organize your content")
                )
            } else {
                ForEach(myLists) { list in
                    NavigationLink {
                        CustomListDetailView(list: list)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(list.name)
                                    .font(.headline)
                                Text("\(list.movieIDs.count) items")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if list.isPublic {
                                Image(systemName: "globe")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            } else {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            context.delete(list)
                            try? context.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateListSheet(userId: userId)
        }
        .task {
            userId = AuthService.shared.currentUserId() ?? "guest"
        }
    }
}

// MARK: - Create List Sheet
struct CreateListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let userId: String

    @State private var listName = ""
    @State private var listDescription = ""
    @State private var isPublic = false

    var body: some View {
        NavigationStack {
            Form {
                Section("List Info") {
                    TextField("List Name", text: $listName)
                    TextField("Description (optional)", text: $listDescription)
                }

                Section("Privacy") {
                    Toggle(isOn: $isPublic) {
                        HStack {
                            Image(systemName: isPublic ? "globe" : "lock.fill")
                                .foregroundStyle(isPublic ? .blue : .secondary)
                            VStack(alignment: .leading) {
                                Text(isPublic ? "Public" : "Private")
                                    .font(.body)
                                Text(isPublic ? "Anyone can see this list" : "Only you can see this list")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New List")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createList()
                    }
                    .disabled(listName.isEmpty)
                }
            }
        }
    }

    private func createList() {
        let newList = CustomList(
            name: listName,
            details: listDescription,
            ownerId: userId,
            isPublic: isPublic
        )
        context.insert(newList)
        try? context.save()

        Task {
            await ListService.shared.uploadList(newList)
        }

        dismiss()
    }
}

// MARK: - Custom List Detail View
struct CustomListDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var list: CustomList
    @Query private var allMovies: [Movie]
    @State private var showEditSheet = false

    var listMovies: [Movie] {
        allMovies.filter { list.movieIDs.contains($0.id) }
    }

    var body: some View {
        List {
            if listMovies.isEmpty {
                ContentUnavailableView(
                    "Empty List",
                    systemImage: "film",
                    description: Text("Add movies from their detail page")
                )
            } else {
                ForEach(listMovies) { movie in
                    NavigationLink {
                        MovieInfoView(
                            tmdb: TMDbItem(
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
                            ),
                            mediaType: movie.mediaType
                        )
                    } label: {
                        HStack(spacing: 12) {
                            PosterThumb(posterPath: movie.posterPath, title: movie.title, width: 50)
                                .cornerRadius(6)
                            VStack(alignment: .leading) {
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
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            list.movieIDs.removeAll { $0 == movie.id }
                            try? context.save()
                            Task { await ListService.shared.uploadList(list) }
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(list.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditListSheet(list: list)
        }
    }
}

// MARK: - Edit List Sheet
struct EditListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var list: CustomList

    @State private var listName: String = ""
    @State private var listDescription: String = ""
    @State private var isPublic: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("List Info") {
                    TextField("List Name", text: $listName)
                    TextField("Description", text: $listDescription)
                }

                Section("Privacy") {
                    Toggle(isOn: $isPublic) {
                        HStack {
                            Image(systemName: isPublic ? "globe" : "lock.fill")
                                .foregroundStyle(isPublic ? .blue : .secondary)
                            VStack(alignment: .leading) {
                                Text(isPublic ? "Public" : "Private")
                                    .font(.body)
                                Text(isPublic ? "Anyone can see this list" : "Only you can see this list")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit List")
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
                    .disabled(listName.isEmpty)
                }
            }
            .onAppear {
                listName = list.name
                listDescription = list.details
                isPublic = list.isPublic
            }
        }
    }

    private func saveChanges() {
        list.name = listName
        list.details = listDescription
        list.isPublic = isPublic
        try? context.save()

        Task {
            await ListService.shared.uploadList(list)
        }

        dismiss()
    }
}

#Preview {
    YourListView()
}
