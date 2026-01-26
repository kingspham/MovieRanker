import SwiftUI
import SwiftUI
import SwiftData

// MARK: - LabelsWrap using adaptive grid (robust, simpler)
struct LabelsWrap: View {
    let all: [String]
    @Binding var selected: Set<String>

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 80), spacing: 8)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(all, id: \.self) { tag in
                let isOn = selected.contains(tag)
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(isOn ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .stroke(isOn ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1)
                    )
                    .onTapGesture {
                        if isOn { selected.remove(tag) } else { selected.insert(tag) }
                    }
            }
        }
    }
}

// MARK: - LogMovieDetailsView
struct LogMovieDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    // Pre-filled values coming from the previous screen (or SearchView)
    let pendingTitle: String?
    let pendingYear: Int?

    // TMDb linkage passed from Search
    let pendingTMDbID: Int?
    let pendingPosterPath: String?
    let pendingGenreIDs: [Int]?
    let pendingPopularity: Double?

    // Callback to let caller refresh (e.g., banner, navigation)
    var onFinish: ((Movie) -> Void)?

    // Form state
    @State private var title: String
    @State private var yearText: String
    @State private var watchedOn: Date = Date()
    @State private var whereWatched: WatchLocation = .other
    @State private var withWho: String = ""
    @State private var notes: String = ""
    @State private var selectedLabels: Set<String> = []

    private let labelOptions = ["Emotional", "Mind-bending", "Cozy", "Action", "Slow burn"]

    init(
        pendingTitle: String? = nil,
        pendingYear: Int? = nil,
        pendingTMDbID: Int? = nil,
        pendingPosterPath: String? = nil,
        pendingGenreIDs: [Int]? = nil,
        pendingPopularity: Double? = nil,
        onFinish: ((Movie) -> Void)? = nil
    ) {
        self.pendingTitle = pendingTitle
        self.pendingYear = pendingYear
        self.pendingTMDbID = pendingTMDbID
        self.pendingPosterPath = pendingPosterPath
        self.pendingGenreIDs = pendingGenreIDs
        self.pendingPopularity = pendingPopularity
        self.onFinish = onFinish

        _title = State(initialValue: pendingTitle ?? "")
        _yearText = State(initialValue: pendingYear != nil ? String(pendingYear!) : "")
    }

    var body: some View {
        Form {
            Section("Confirm movie") {
                #if os(iOS)
                TextField("Title", text: $title)
                    .textInputAutocapitalization(.words)
                #else
                TextField("Title", text: $title)
                #endif
                #if os(iOS)
                TextField("Year (optional)", text: $yearText)
                    .keyboardType(.numberPad)
                #else
                TextField("Year (optional)", text: $yearText)
                #endif
            }

            Section("Watch details") {
                DatePicker("Watched on", selection: $watchedOn, displayedComponents: .date)
                Picker("Where", selection: $whereWatched) {
                    ForEach(WatchLocation.allCases, id: \.self) { loc in
                        Text(loc.rawValue.capitalized).tag(loc)
                    }
                }
                TextField("With who (optional)", text: $withWho)
            }

            Section("Notes") {
                TextEditor(text: $notes).frame(minHeight: 120)
            }

            Section("Labels") {
                LabelsWrap(all: labelOptions, selected: $selectedLabels)
                    .padding(.vertical, 4)
            }

            Section {
                Button("Save") {
                    Task {
                        await saveAndCloseAsync()
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Cancel", role: .cancel) { dismiss() }
            }
        }
        .navigationTitle("Log details")
    }

    // MARK: - Save
    @MainActor
    private func saveAndCloseAsync() async {
        let t0 = CFAbsoluteTimeGetCurrent()

        // Prepare inputs
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleLower = trimmed.lowercased()
        let yr: Int? = Int(yearText.trimmingCharacters(in: .whitespacesAndNewlines))

        guard !trimmed.isEmpty else { return }

        // Prefer a store-level fetch over scanning @Query to avoid UI stalls
        var movieFD: FetchDescriptor<Movie>
        if let yr = yr {
            movieFD = FetchDescriptor<Movie>(
                predicate: #Predicate<Movie> { $0.titleLower == titleLower && $0.year == yr }
            )
        } else {
            movieFD = FetchDescriptor<Movie>(
                predicate: #Predicate<Movie> { $0.titleLower == titleLower }
            )
        }
        movieFD.fetchLimit = 1

        let existing = (try? context.fetch(movieFD).first) ?? nil

        #if DEBUG
        print("[LogDetails] Fetch took \(CFAbsoluteTimeGetCurrent() - t0)s")
        #endif

        // Upsert movie
        let owner = SessionManager.shared.userId ?? "unknown"
        let movie: Movie
        if let m = existing {
            movie = m
        } else {
            movie = Movie(title: trimmed, year: yr, ownerId: owner)
            context.insert(movie)
        }

        // Create a new log entry
        let entry = LogEntry(
            id: UUID(),
            createdAt: Date(),
            rating: nil,
            watchedOn: watchedOn,
            whereWatched: whereWatched,
            withWho: withWho.isEmpty ? nil : withWho,
            notes: notes.isEmpty ? nil : notes,
            labels: selectedLabels.isEmpty ? nil : Array(selectedLabels),
            movie: movie,
            ownerId: owner
        )
        context.insert(entry)

        // Ensure Score exists
        let movieIDValue = movie.id
        var scoreFD = FetchDescriptor<Score>(
            predicate: #Predicate<Score> { $0.movieID == movieIDValue }
        )
        scoreFD.fetchLimit = 1
        if let found: [Score] = try? context.fetch(scoreFD), found.isEmpty {
            context.insert(Score(movieID: movieIDValue, display100: 50, latent: 0.0, variance: 1.0, ownerId: owner))
        }

        do {
            try context.save()
        } catch {
            print("Save failed:", error.localizedDescription)
        }

        #if DEBUG
        print("[LogDetails] Total save flow took \(CFAbsoluteTimeGetCurrent() - t0)s")
        #endif

        // Dismiss first to avoid re-entrant heavy work during sheet closure
        dismiss()
        // Fire the callback shortly after dismissal to avoid blocking transitions
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            onFinish?(movie)
        }
    }
}

