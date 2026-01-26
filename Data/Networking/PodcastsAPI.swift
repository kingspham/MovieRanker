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
}
