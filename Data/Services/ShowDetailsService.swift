import Foundation

struct ShowDetails: Decodable, Sendable {
    let title: String
    let year: String
    let imdbRating: String?
    let metascore: String?
    let rottenTomatoes: String?
}

enum ShowDetailsError: Error { case missingAPIKey, notFound, badResponse }

final class ShowDetailsService {
    // Use Config
    private let fallbackKey = Config.omdbApiKey

    func lookupByTitle(_ title: String, year: Int? = nil) async throws -> ShowDetails {
        // 1. Try with Year
        if let result = await fetch(title: title, year: year) { return result }
        // 2. Retry without Year
        if year != nil {
            if let result = await fetch(title: title, year: nil) { return result }
        }
        throw ShowDetailsError.notFound
    }
    
    private func fetch(title: String, year: Int?) async -> ShowDetails? {
        let safeTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        var urlString = "https://www.omdbapi.com/?apikey=\(fallbackKey)&t=\(safeTitle)"
        if let y = year { urlString += "&y=\(y)" }
        
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct OMDbResponse: Decodable {
                let Title: String?
                let Year: String?
                let imdbRating: String?
                let Metascore: String?
                let Ratings: [RatingObj]?
                let Response: String
            }
            struct RatingObj: Decodable { let Source: String; let Value: String }

            let obj = try JSONDecoder().decode(OMDbResponse.self, from: data)
            guard obj.Response == "True", let t = obj.Title else { return nil }

            let rt = obj.Ratings?.first(where: { $0.Source == "Rotten Tomatoes" })?.Value
            var meta = obj.Metascore
            if meta == nil || meta == "N/A" {
                meta = obj.Ratings?.first(where: { $0.Source == "Metacritic" })?.Value.components(separatedBy: "/").first
            }

            return ShowDetails(title: t, year: obj.Year ?? "", imdbRating: obj.imdbRating, metascore: meta, rottenTomatoes: rt)
        } catch {
            print("❌ OMDb Fetch Error: \(error)")
            return nil
        }
    }
}
