import SwiftUI
import SwiftData

struct TMDbMovieDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let tmdb: TMDbMovie

    // UI state
    @State private var working = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    PosterThumb(path: tmdb.posterPath, width: 80, height: 120)
                        .frame(width: 80, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tmdb.title).font(.title3).bold()
                        if let y = tmdb.year { Text("\(y)").foregroundStyle(.secondary) }
                    }
                    Spacer()
                }

                if let msg = errorMessage {
                    Text(msg)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                VStack(spacing: 10) {
                    Button {
                        Task { await saveToLibrary(addToWatchlist: false, rateAfter: false) }
                    } label: {
                        Label("Save to Library", systemImage: "tray.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task { await saveToLibrary(addToWatchlist: true, rateAfter: false) }
                    } label: {
                        Label("Add to Watch List", systemImage: "bookmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await saveToLibrary(addToWatchlist: false, rateAfter: true) }
                    } label: {
                        Label("Rate Now", systemImage: "star")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .overlay {
                if working {
                    ZStack {
                        Color.black.opacity(0.05).ignoresSafeArea()
                        ProgressView()
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func normalizedTitle(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    @MainActor
    private func saveToLibrary(addToWatchlist: Bool, rateAfter: Bool) async {
        guard !tmdb.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        working = true
        defer { working = false }
        errorMessage = nil

        do {
            // Try upsert by tmdbID first if possible
            let existing: Movie? = try findExistingMovie()
            let movie: Movie
            if let m = existing {
                movie = m
            } else {
                // Create new Movie with TMDb metadata
                let m = Movie(
                    title: tmdb.title,
                    year: tmdb.year,
                    tmdbID: tmdb.id,
                    posterPath: tmdb.posterPath,
                    genreIDs: tmdb.genreIDs,
                    popularity: tmdb.popularity,
                    ownerId: SessionManager.shared.userId
                )
                // Ensure normalized titleLower if the model has it
                if let mirror = try? Mirror(reflecting: m).children.first(where: { $0.label == "titleLower" }), mirror != nil {
                    m.titleLower = tmdb.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                }
                context.insert(m)
                movie = m
            }

            // Ensure Score exists
            var scoreFD = FetchDescriptor<Score>(predicate: #Predicate { $0.movieID == movie.id })
            scoreFD.fetchLimit = 1
            if let found: [Score] = try? context.fetch(scoreFD), found.isEmpty {
                context.insert(Score(movieID: movie.id, display100: 50, latent: 0.0, variance: 1.0, ownerId: SessionManager.shared.userId))
            }

            // Add to watchlist if requested
            if addToWatchlist {
                // Check if already in watchlist
                let items: [UserItem] = (try? context.fetch(FetchDescriptor<UserItem>())) ?? []
                if items.first(where: { $0.movie?.id == movie.id && $0.state == .watchlist }) == nil {
                    context.insert(UserItem(movie: movie, state: .watchlist, ownerId: SessionManager.shared.userId))
                }
            }

            try context.save()

            if rateAfter {
                // Dismiss and present Compare anchored on this movie
                let id = movie.id
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    // Post a notification so a coordinator can present CompareView(anchorID:)
                    NotificationCenter.default.post(name: .presentCompareForMovie, object: id)
                }
            } else {
                // Dismiss with a success notification
                let title = movie.title
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NotificationCenter.default.post(name: .movieDidSave, object: title)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func findExistingMovie() throws -> Movie? {
        // Prefer tmdbID match when available
        var byTMDb = FetchDescriptor<Movie>(predicate: #Predicate { $0.tmdbID == tmdb.id })
        byTMDb.fetchLimit = 1
        if let found = try? context.fetch(byTMDb), let m = found.first { return m }

        // Fallback to normalized title/year
        let titleLower = normalizedTitle(tmdb.title)
        if let y = tmdb.year {
            var fd = FetchDescriptor<Movie>(predicate: #Predicate { $0.titleLower == titleLower && $0.year == y })
            fd.fetchLimit = 1
            if let found = try? context.fetch(fd), let m = found.first { return m }
        } else {
            var fd = FetchDescriptor<Movie>(predicate: #Predicate { $0.titleLower == titleLower })
            fd.fetchLimit = 1
            if let found = try? context.fetch(fd), let m = found.first { return m }
        }
        return nil
    }
}

extension Notification.Name {
    static let movieDidSave = Notification.Name("movieDidSave")
    static let presentCompareForMovie = Notification.Name("presentCompareForMovie")
}
