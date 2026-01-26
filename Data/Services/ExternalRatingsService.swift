// ExternalRatingsService.swift
// REPLACE your ExternalRatingsService.swift with this
// Fetches IMDb, Rotten Tomatoes, and Metacritic ratings

import Foundation

struct ExternalRatings: Sendable, Equatable {
    let imdb: String?
    let metacritic: String?
    let rottenTomatoes: String?
    
    var hasAnyRating: Bool {
        imdb != nil || metacritic != nil || rottenTomatoes != nil
    }
}

enum ExternalRatingsService {
    
    static func fetch(forTitle title: String, year: Int?) async throws -> ExternalRatings {
        let apiKey = Config.omdbApiKey
        
        // Clean title for URL
        let cleanTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        
        // Build URL
        var urlString = "https://www.omdbapi.com/?apikey=\(apiKey)&t=\(cleanTitle)"
        if let year = year {
            urlString += "&y=\(year)"
        }
        
        guard let url = URL(string: urlString) else {
            return ExternalRatings(imdb: nil, metacritic: nil, rottenTomatoes: nil)
        }
        
        print("🎬 Fetching ratings for: \(title)")
        
        // Fetch data
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Parse response
        let response = try JSONDecoder().decode(OMDbResponse.self, from: data)
        
        guard response.response == "True" else {
            print("⚠️ OMDb: \(response.error ?? "No results")")
            return ExternalRatings(imdb: nil, metacritic: nil, rottenTomatoes: nil)
        }
        
        // Extract ratings
        var imdb: String?
        var metacritic: String?
        var rottenTomatoes: String?
        
        // IMDb rating
        if let imdbRating = response.imdbRating, imdbRating != "N/A" {
            imdb = imdbRating
        }
        
        // Metacritic rating
        if let metascore = response.metascore, metascore != "N/A" {
            metacritic = metascore
        }
        
        // Parse ratings array for Rotten Tomatoes
        if let ratings = response.ratings {
            for rating in ratings {
                if rating.source == "Rotten Tomatoes" {
                    rottenTomatoes = rating.value
                    break
                }
            }
        }
        
        print("✅ Ratings - IMDb: \(imdb ?? "N/A"), RT: \(rottenTomatoes ?? "N/A"), Meta: \(metacritic ?? "N/A")")
        
        return ExternalRatings(
            imdb: imdb,
            metacritic: metacritic,
            rottenTomatoes: rottenTomatoes
        )
    }
}

// MARK: - OMDb API Models

private struct OMDbResponse: Decodable {
    let response: String
    let error: String?
    let imdbRating: String?
    let metascore: String?
    let ratings: [OMDbRating]?
    
    enum CodingKeys: String, CodingKey {
        case response = "Response"
        case error = "Error"
        case imdbRating = "imdbRating"
        case metascore = "Metascore"
        case ratings = "Ratings"
    }
}

private struct OMDbRating: Decodable {
    let source: String
    let value: String
    
    enum CodingKeys: String, CodingKey {
        case source = "Source"
        case value = "Value"
    }
}
