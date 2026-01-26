import Foundation

extension ExternalRatingsService {
    /// Ratings/plot for a TV series via OMDb.
    static func fetchShow(forTitle title: String, yearStart: Int?) async throws -> ExternalRatings {
        var comps = URLComponents(string: "https://www.omdbapi.com/")!
        var items = [URLQueryItem(name: "apikey", value: "c7955ee3"),
                     URLQueryItem(name: "t", value: title),
                     URLQueryItem(name: "type", value: "series")]
        if let y = yearStart { items.append(.init(name: "y", value: String(y))) }
        comps.queryItems = items

        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let plot = json?["Plot"] as? String
        let imdb = json?["imdbRating"] as? String
        let metascore = json?["Metascore"] as? String

        var rt: String?
        if let ratings = json?["Ratings"] as? [[String: Any]] {
            rt = ratings.first(where: { ($0["Source"] as? String) == "Rotten Tomatoes" })?["Value"] as? String
        }

        return ExternalRatings(imdb: imdb, rottenTomatoes: rt, metacritic: metascore, plot: plot)
    }
}
