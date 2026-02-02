import Foundation

struct iTunesResponse: Decodable {
    let results: [iTunesPodcast]
}

struct iTunesPodcast: Decodable {
    let collectionId: Int
    let collectionName: String
    let artistName: String
    let artworkUrl600: String?
    let releaseDate: String?
    let genres: [String]? // <--- iTunes gives strings
}

// Top Podcasts response
struct iTunesTopResponse: Decodable {
    let feed: iTunesFeed?
}

struct iTunesFeed: Decodable {
    let results: [iTunesTopPodcast]?
}

struct iTunesTopPodcast: Decodable {
    let id: String
    let name: String
    let artistName: String
    let artworkUrl100: String?
    let genres: [iTunesGenre]?
}

struct iTunesGenre: Decodable {
    let name: String
}

actor PodcastsAPI {
    private let session = URLSession.shared
    private let baseUrl = "https://itunes.apple.com/search"

    func search(query: String) async throws -> [TMDbItem] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseUrl)?term=\(encoded)&media=podcast&entity=podcast") else { return [] }

        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(iTunesResponse.self, from: data)

        return response.results.map { item in
            return TMDbItem(
                id: item.collectionId,
                title: item.collectionName,
                overview: "Hosted by \(item.artistName)",
                releaseDate: item.releaseDate,
                posterPath: item.artworkUrl600,
                genreIds: [],
                tags: item.genres, // <--- SAVING TAGS
                mediaType: "podcast"
            )
        }
    }

    /// Get top/popular podcasts from iTunes
    func getTopPodcasts() async throws -> [TMDbItem] {
        guard let url = URL(string: "https://itunes.apple.com/us/rss/toppodcasts/limit=15/json") else {
            return []
        }

        do {
            let (data, _) = try await session.data(from: url)

            // iTunes RSS feed has a different structure
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let feed = json["feed"] as? [String: Any],
               let entries = feed["entry"] as? [[String: Any]] {

                return entries.prefix(10).compactMap { entry -> TMDbItem? in
                    guard let idDict = entry["id"] as? [String: Any],
                          let attributes = idDict["attributes"] as? [String: Any],
                          let idStr = attributes["im:id"] as? String,
                          let id = Int(idStr),
                          let nameDict = entry["im:name"] as? [String: Any],
                          let name = nameDict["label"] as? String else {
                        return nil
                    }

                    // Get artist name
                    var artistName = ""
                    if let artistDict = entry["im:artist"] as? [String: Any],
                       let artist = artistDict["label"] as? String {
                        artistName = artist
                    }

                    // Get artwork URL
                    var artworkUrl: String? = nil
                    if let images = entry["im:image"] as? [[String: Any]],
                       let lastImage = images.last,
                       let imageUrl = lastImage["label"] as? String {
                        // Replace size to get larger image
                        artworkUrl = imageUrl.replacingOccurrences(of: "55x55", with: "600x600")
                            .replacingOccurrences(of: "170x170", with: "600x600")
                    }

                    // Get genres
                    var genres: [String] = []
                    if let category = entry["category"] as? [String: Any],
                       let catAttrs = category["attributes"] as? [String: Any],
                       let genreName = catAttrs["label"] as? String {
                        genres.append(genreName)
                    }

                    return TMDbItem(
                        id: id,
                        title: name,
                        overview: "Hosted by \(artistName)",
                        releaseDate: nil,
                        posterPath: artworkUrl,
                        genreIds: [],
                        tags: genres.isEmpty ? nil : genres,
                        mediaType: "podcast"
                    )
                }
            }
        } catch {
            print("🎙 PodcastsAPI: Error fetching top podcasts: \(error)")
        }

        return []
    }
}
