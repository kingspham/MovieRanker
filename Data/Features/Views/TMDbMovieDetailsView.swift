import SwiftUI
import SwiftData

struct TMDbMovieDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let tmdb: TMDbMovie   // via MRCompat -> MRMovieSummary

    // UI state
    @State private var working = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    // Build a full TMDb image URL (posterPath is just "/path.jpg")
                    let posterURL = TMDbClient.makeImageURL(path: tmdb.posterPath, size: .w185)

                    AsyncImage(url: posterURL) { phase in
                        switch phase {
                        case .empty:
                            ZStack {
                                RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15))
                                ProgressView()
                            }
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            ZStack {
                                RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15))
                                Image(systemName: "photo")
                                    .imageScale(.large)
                                    .foregroundStyle(.secondary)
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: 80, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(tmdb.title).font(.title3).bold()
                        if let y = tmdb.year {
                            Text("\(y)").foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                if let msg = errorMessage {
                    Text(msg).foregroundStyle(.red).font(.footnote)
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
                    ownerId: SessionManager.shared.userId ?? "local"
                )
                // Set normalized titleLower if your model has it
                if Mirror(reflecting: m).children.contains(where: { $0.label == "titleLower" }) {
                    m.titleLower = tmdb.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                }
                context.insert(m)
                movie = m
            }

            // Ensure Score exists
            let movieID = movie.id
            var scoreFD = FetchDescriptor<Score>(predicate: #Predicate { $0.movieID == movieID })
            scoreFD.fetchLimit = 1
            let scoreCount = (try? context.fetchCount(scoreFD)) ?? 0
            if scoreCount == 0 {
                context.insert(
                    Score(
                        movieID: movieID,
                        display100: 50,
                        latent: 0.0,
                        variance: 1.0,
                        ownerId: SessionManager.shared.userId ?? "local"
                    )
                )
            }

            // Add to watchlist if requested
            if addToWatchlist {
                let items: [UserItem] = (try? context.fetch(FetchDescriptor<UserItem>())) ?? []
                if items.first(where: { $0.movie?.id == movie.id && $0.state == .watchlist }) == nil {
                    context.insert(
                        UserItem(
                            movie: movie,
                            state: .watchlist,
                            ownerId: SessionManager.shared.userId ?? "local"
                        )
                    )
                }
            }

            try context.save()

            if rateAfter {
                let id = movie.id
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(name: .presentCompareForMovie, object: id)
                }
            } else {
                let title = movie.title
                let id = movie.id
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NotificationCenter.default.post(name: .movieDidSave, object: title)
                    NotificationCenter.default.post(name: .presentMovieDetails, object: id)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func findExistingMovie() throws -> Movie? {
        // Prefer tmdbID match when available
        do {
            let tmdbIDToMatch: Int? = tmdb.id
            var byTMDb = FetchDescriptor<Movie>(predicate: #Predicate { $0.tmdbID == tmdbIDToMatch })
            byTMDb.fetchLimit = 1
            if let found = try context.fetch(byTMDb).first { return found }
        } catch { /* fall through */ }

        // Fallback to normalized title/year
        let titleLower = normalizedTitle(tmdb.title)
        if let y = tmdb.year {
            var fd = FetchDescriptor<Movie>(predicate: #Predicate { $0.titleLower == titleLower && $0.year == y })
            fd.fetchLimit = 1
            if let found = try context.fetch(fd).first { return found }
        } else {
            var fd = FetchDescriptor<Movie>(predicate: #Predicate { $0.titleLower == titleLower })
            fd.fetchLimit = 1
            if let found = try context.fetch(fd).first { return found }
        }
        return nil
    }
}

extension Notification.Name {
    static let movieDidSave = Notification.Name("movieDidSave")
    static let presentCompareForMovie = Notification.Name("presentCompareForMovie")
    static let presentMovieDetails = Notification.Name("presentMovieDetails")
}
