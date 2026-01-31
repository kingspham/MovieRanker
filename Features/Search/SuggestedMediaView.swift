import SwiftUI
import SwiftData

struct SuggestedMediaView: View {
    let userId: String
    let mediaType: String
    
    @Environment(\.modelContext) private var context
    
    @State private var items: [TMDbItem] = []
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView("No Suggestions", systemImage: "sparkles")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items, id: \.id) { item in
                    NavigationLink(value: item) {
                        HStack(spacing: 16) {
                            PosterThumb(url: item.posterPath, title: item.title ?? item.name ?? "Unknown")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title ?? item.name ?? "Unknown")
                                    .font(.headline)
                                    .lineLimit(1)
                                if let releaseDate = item.releaseDate ?? item.firstAirDate {
                                    Text(releaseDate)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                if let overview = item.overview, !overview.isEmpty {
                                    Text(overview)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .navigationDestination(for: TMDbItem.self) { item in
                        MovieInfoView(tmdb: item, mediaType: mediaType)
                            .modelContext(context)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(navigationTitle)
        .task {
            await loadSuggestions()
        }
    }
    
    private var navigationTitle: String {
        switch mediaType {
        case "movie":
            return "Suggested Movies"
        case "tv":
            return "Suggested Shows"
        default:
            return "Suggested"
        }
    }
    
    private func loadSuggestions() async {
        isLoading = true
        do {
            let client = try TMDbClient()
            if mediaType == "movie" {
                do {
                    let response = try await client.discoverByGenres(genreIds: [])
                    self.items = response.results
                } catch {
                    let fallback = try await client.getTrending()
                    self.items = fallback.results.filter { $0.mediaType == "movie" }
                }
            } else if mediaType == "tv" {
                do {
                    let response = try await client.discoverTVByGenres(genreIds: [])
                    self.items = response.results
                } catch {
                    let fallback = try await client.getTrending()
                    self.items = fallback.results.filter { $0.mediaType == "tv" }
                }
            } else {
                self.items = []
            }
        } catch {
            print("Failed to load suggestions: \(error)")
            self.items = []
        }
        isLoading = false
    }
}
