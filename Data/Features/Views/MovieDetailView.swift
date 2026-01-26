import SwiftUI
import SwiftData

struct MovieDetailView: View {
    @Environment(\.modelContext) private var context
    let movie: Movie

    @State private var ext: ExternalRatings? = nil
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    PosterThumb(posterPath: movie.posterPath, title: movie.title, width: 90)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(movie.title).font(.title3).bold()
                        if let y = movie.year {
                            Text(String(y)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                if let ext {
                    ratingsGrid(ext)
                    if let plot = ext.plot, !plot.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Overview").font(.headline)
                            Text(plot)
                        }
                    }
                } else if loading {
                    ProgressView("Loading ratings…")
                }

                Divider().padding(.vertical, 4)

                // Your existing sections (reviews, log entries, etc.) can go here
            }
            .padding()
        }
        .navigationTitle(movie.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadExternalRatings()
        }
    }

    private func ratingsGrid(_ e: ExternalRatings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ratings").font(.headline)
            HStack(spacing: 12) {
                if let v = e.imdb { badge("IMDb", v) }
                if let v = e.rottenTomatoes { badge("Rotten Tomatoes", v) }
                if let v = e.metacritic { badge("Metacritic", v) }
            }
        }
    }

    private func badge(_ source: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(source).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).bold()
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func loadExternalRatings() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            ext = try await ExternalRatingsService.fetch(forTitle: movie.title, year: movie.year)
        } catch {
            ext = nil
        }
    }
}
