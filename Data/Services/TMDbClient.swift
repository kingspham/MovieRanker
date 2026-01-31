// TMDbClient.swift
// COMPLETE REPLACEMENT

import Foundation

// MARK: - DTOs

public struct TMDbItem: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let overview: String?
    public let posterPath: String?
    public let genreIds: [Int]?
    public let mediaType: String?

    // Person-specific field (profile image)
    public let profilePath: String?

    // Default to nil for optional fields that don't come from TMDb
    public var tags: [String]? = nil

    private let title: String?
    private let name: String?
    private let releaseDate: String?
    private let firstAirDate: String?

    // Added popularity for sorting
    public let popularity: Double?

    public init(id: Int, title: String? = nil, name: String? = nil, overview: String? = nil, releaseDate: String? = nil, firstAirDate: String? = nil, posterPath: String? = nil, profilePath: String? = nil, genreIds: [Int]? = nil, tags: [String]? = nil, mediaType: String? = "movie", popularity: Double? = nil) {
        self.id = id
        self.title = title
        self.name = name
        self.overview = overview
        self.releaseDate = releaseDate
        self.firstAirDate = firstAirDate
        self.posterPath = posterPath
        self.profilePath = profilePath
        self.genreIds = genreIds
        self.tags = tags
        self.mediaType = mediaType
        self.popularity = popularity
    }

    public var displayTitle: String { title ?? name ?? "Unknown" }
    public var year: Int? {
        let ds = releaseDate ?? firstAirDate
        guard let s = ds, s.count >= 4, let y = Int(s.prefix(4)) else { return nil }
        return y
    }

    /// Returns the best available image path (posterPath for movies/shows, profilePath for people)
    public var imagePath: String? {
        posterPath ?? profilePath
    }

    public func type(fallback: String) -> String { mediaType ?? fallback }

    private enum CodingKeys: String, CodingKey {
        case id, title, name, overview, popularity
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case posterPath  = "poster_path"
        case profilePath = "profile_path"
        case genreIds    = "genre_ids"
        case mediaType   = "media_type"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        overview = try container.decodeIfPresent(String.self, forKey: .overview)
        releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate)
        firstAirDate = try container.decodeIfPresent(String.self, forKey: .firstAirDate)
        posterPath = try container.decodeIfPresent(String.self, forKey: .posterPath)
        profilePath = try container.decodeIfPresent(String.self, forKey: .profilePath)
        genreIds = try container.decodeIfPresent([Int].self, forKey: .genreIds)
        mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
        popularity = try container.decodeIfPresent(Double.self, forKey: .popularity)
    }
}

public typealias TMDbMovie = TMDbItem

public struct TMDbPagedResponse<T: Decodable & Sendable>: Decodable, Sendable {
    public let page: Int
    public let results: [T]
    public let totalPages: Int?
    public let totalResults: Int?
    
    private enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }
}

// TV Details
public struct TMDbTVDetail: Decodable, Sendable {
    public let id: Int
    public let name: String
    public let seasons: [TMDbSeason]?
    
    public struct TMDbSeason: Decodable, Sendable, Identifiable {
        public let id: Int
        public let name: String
        public let seasonNumber: Int
        public let posterPath: String?
        public let episodeCount: Int?
        public let airDate: String?
        
        private enum CodingKeys: String, CodingKey {
            case id, name
            case seasonNumber = "season_number"
            case posterPath = "poster_path"
            case episodeCount = "episode_count"
            case airDate = "air_date"
        }
    }
}

// Watch Providers
public struct WatchProviderResponse: Decodable, Sendable {
    let results: [String: CountryProviders]?
}
public struct CountryProviders: Decodable, Sendable {
    let flatrate: [ProviderItem]?
    let rent: [ProviderItem]?
    let buy: [ProviderItem]?
}
public struct ProviderItem: Decodable, Sendable, Identifiable {
    public let providerId: Int
    public let providerName: String
    public let logoPath: String?
    public var id: Int { providerId }
    
    private enum CodingKeys: String, CodingKey {
        case providerId = "provider_id"
        case providerName = "provider_name"
        case logoPath = "logo_path"
    }
}

// Credits
public struct CreditsResponse: Decodable, Sendable {
    public let cast: [CastMember]
    public let crew: [CrewMember]
}
public struct CastMember: Decodable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let character: String?
    public let profilePath: String?
    public let popularity: Double?
    private enum CodingKeys: String, CodingKey { case id, name, character, popularity; case profilePath = "profile_path" }
}
public struct CrewMember: Decodable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let job: String
    public let profilePath: String?
    private enum CodingKeys: String, CodingKey { case id, name, job; case profilePath = "profile_path" }
}

// Details & Person - Enhanced for prediction engine
public struct TMDbMovieDetail: Decodable, Sendable {
    public let id: Int
    public let genres: [Genre]?
    public let runtime: Int?
    public let budget: Int?
    public let revenue: Int?
    public let voteAverage: Double?
    public let voteCount: Int?
    public let originalLanguage: String?
    public let productionCountries: [ProductionCountry]?
    public let spokenLanguages: [SpokenLanguage]?
    public let status: String?
    public let tagline: String?

    public struct Genre: Decodable, Sendable { let id: Int; let name: String }
    public struct ProductionCountry: Decodable, Sendable {
        let iso31661: String
        let name: String
        private enum CodingKeys: String, CodingKey {
            case iso31661 = "iso_3166_1"
            case name
        }
    }
    public struct SpokenLanguage: Decodable, Sendable {
        let iso6391: String
        let name: String
        private enum CodingKeys: String, CodingKey {
            case iso6391 = "iso_639_1"
            case name
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, genres, runtime, budget, revenue, status, tagline
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case originalLanguage = "original_language"
        case productionCountries = "production_countries"
        case spokenLanguages = "spoken_languages"
    }
}

// TV Show Details - Enhanced
public struct TMDbTVShowDetail: Decodable, Sendable {
    public let id: Int
    public let genres: [TMDbMovieDetail.Genre]?
    public let episodeRunTime: [Int]?
    public let voteAverage: Double?
    public let voteCount: Int?
    public let originalLanguage: String?
    public let productionCountries: [TMDbMovieDetail.ProductionCountry]?
    public let status: String?
    public let numberOfSeasons: Int?
    public let numberOfEpisodes: Int?
    public let originCountry: [String]?

    private enum CodingKeys: String, CodingKey {
        case id, genres, status
        case episodeRunTime = "episode_run_time"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case originalLanguage = "original_language"
        case productionCountries = "production_countries"
        case numberOfSeasons = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
        case originCountry = "origin_country"
    }
}

// Keywords response
public struct KeywordsResponse: Decodable, Sendable {
    public let id: Int?
    public let keywords: [Keyword]?
    public let results: [Keyword]? // TV shows use "results" instead of "keywords"

    public struct Keyword: Decodable, Sendable {
        public let id: Int
        public let name: String
    }

    // Get all keywords regardless of response type
    public var allKeywords: [Keyword] {
        return keywords ?? results ?? []
    }
}
public struct PersonDetail: Decodable, Sendable {
    public let id: Int
    public let name: String
    public let biography: String?
    public let birthday: String?
    public let placeOfBirth: String?
    public let profilePath: String?
    private enum CodingKeys: String, CodingKey {
        case id, name, biography, birthday
        case placeOfBirth = "place_of_birth"
        case profilePath = "profile_path"
    }
}
public struct TMDbPersonCredits: Decodable, Sendable { public let cast: [TMDbItem] }


// MARK: - Client

public enum TMDbError: Error, LocalizedError {
    case missingAPIKey, badURL, http(Int), decoding(Error), transport(Error)
}

public actor TMDbClient {
    public enum ImageSize: String { case w185, w342, w500, w780, original }

    private let apiKey: String
    private let base = URL(string: "https://api.themoviedb.org/3")!
    private let session: URLSession

    public init(session: URLSession = .shared) throws {
        self.apiKey = Config.tmdbApiKey
        self.session = session
    }

    public static func makeImageURL(path: String?, size: ImageSize) -> URL? {
        guard let p = path else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size.rawValue)\(p)")
    }

    // MARK: - Endpoints

    public func searchMulti(query: String, page: Int = 1) async throws -> TMDbPagedResponse<TMDbItem> {
        try await request(path: "/search/multi", items: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "include_adult", value: "false")
        ])
    }
    
    public func searchMovies(query: String, page: Int = 1) async throws -> TMDbPagedResponse<TMDbItem> {
        try await request(path: "/search/movie", items: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "include_adult", value: "false")
        ])
    }

    public func popularMovies(page: Int = 1) async throws -> TMDbPagedResponse<TMDbItem> {
        return try await request(path: "/movie/popular", items: [URLQueryItem(name: "page", value: String(page))])
    }
    
    public func popularTV(page: Int = 1) async throws -> TMDbPagedResponse<TMDbItem> {
        let resp: TMDbPagedResponse<TMDbItem> = try await request(path: "/tv/popular", items: [URLQueryItem(name: "page", value: String(page))])
        let fixed = resp.results.map { item -> TMDbItem in
            TMDbItem(id: item.id, title: nil, name: item.displayTitle, overview: item.overview, releaseDate: nil, firstAirDate: item.year.map(String.init), posterPath: item.posterPath, genreIds: item.genreIds, tags: nil, mediaType: "tv")
        }
        return TMDbPagedResponse(page: resp.page, results: fixed, totalPages: resp.totalPages, totalResults: resp.totalResults)
    }
    
    public func getTrending() async throws -> TMDbPagedResponse<TMDbItem> {
        return try await request(path: "/trending/all/day", items: [])
    }
    
    public func getNowPlaying() async throws -> TMDbPagedResponse<TMDbItem> {
        return try await request(path: "/movie/now_playing", items: [
            URLQueryItem(name: "region", value: "US")
        ])
    }
    
    public func getStreaming() async throws -> TMDbPagedResponse<TMDbItem> {
        return try await request(path: "/discover/movie", items: [
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "watch_region", value: "US"),
            URLQueryItem(name: "with_watch_monetization_types", value: "flatrate"),
            URLQueryItem(name: "include_adult", value: "false")
        ])
    }
    
    public func getWatchProviders(id: Int, type: String) async throws -> [ProviderItem] {
        let endpoint = "/\(type)/\(id)/watch/providers"
        let response: WatchProviderResponse = try await request(path: endpoint, items: [])
        let us = response.results?["US"]
        let all = (us?.flatrate ?? []) + (us?.rent ?? []) + (us?.buy ?? [])
        var seen = Set<Int>()
        return all.filter { seen.insert($0.providerId).inserted }
    }
    
    public func getCredits(id: Int, type: String) async throws -> CreditsResponse {
        return try await request(path: "/\(type)/\(id)/credits", items: [])
    }
    
    public func getDetails(id: Int, type: String) async throws -> TMDbMovieDetail {
        return try await request(path: "/\(type)/\(id)", items: [])
    }

    /// Get enhanced TV show details with prediction-relevant fields
    public func getTVShowDetails(id: Int) async throws -> TMDbTVShowDetail {
        return try await request(path: "/tv/\(id)", items: [])
    }

    /// Get keywords for a movie or TV show (used for content-based predictions)
    public func getKeywords(id: Int, type: String) async throws -> [String] {
        let response: KeywordsResponse = try await request(path: "/\(type)/\(id)/keywords", items: [])
        return response.allKeywords.map { $0.name }
    }

    /// Fetch all prediction-relevant data in one call (for movies)
    public func getFullMovieDetails(id: Int) async throws -> (details: TMDbMovieDetail, keywords: [String]) {
        async let details = getDetails(id: id, type: "movie")
        async let keywords = getKeywords(id: id, type: "movie")
        return try await (details, keywords)
    }

    /// Fetch all prediction-relevant data in one call (for TV shows)
    public func getFullTVDetails(id: Int) async throws -> (details: TMDbTVShowDetail, keywords: [String]) {
        async let details = getTVShowDetails(id: id)
        async let keywords = getKeywords(id: id, type: "tv")
        return try await (details, keywords)
    }

    public func getTVDetails(id: Int) async throws -> TMDbTVDetail {
        return try await request(path: "/tv/\(id)", items: [])
    }
    
    public func getPersonDetails(id: Int) async throws -> PersonDetail {
        return try await request(path: "/person/\(id)", items: [])
    }
    
    public func getPersonCredits(id: Int) async throws -> TMDbPersonCredits {
        return try await request(path: "/person/\(id)/combined_credits", items: [])
    }

    /// Get recommendations based on a specific movie
    public func getRecommendations(id: Int, type: String) async throws -> TMDbPagedResponse<TMDbItem> {
        return try await request(path: "/\(type)/\(id)/recommendations", items: [])
    }

    /// Discover movies by genre IDs
    public func discoverByGenres(genreIds: [Int], excludeIds: Set<Int> = [], page: Int = 1) async throws -> TMDbPagedResponse<TMDbItem> {
        let genreString = genreIds.map(String.init).joined(separator: "|")
        return try await request(path: "/discover/movie", items: [
            URLQueryItem(name: "with_genres", value: genreString),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "vote_count.gte", value: "100"),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "page", value: String(page))
        ])
    }

    /// Discover TV shows by genre IDs
    public func discoverTVByGenres(genreIds: [Int], page: Int = 1) async throws -> TMDbPagedResponse<TMDbItem> {
        let genreString = genreIds.map(String.init).joined(separator: "|")
        let resp: TMDbPagedResponse<TMDbItem> = try await request(path: "/discover/tv", items: [
            URLQueryItem(name: "with_genres", value: genreString),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "vote_count.gte", value: "50"),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "page", value: String(page))
        ])
        // Fix media type for TV shows
        let fixed = resp.results.map { item -> TMDbItem in
            TMDbItem(id: item.id, title: nil, name: item.displayTitle, overview: item.overview, releaseDate: nil, firstAirDate: item.year.map(String.init), posterPath: item.posterPath, genreIds: item.genreIds, tags: nil, mediaType: "tv", popularity: item.popularity)
        }
        return TMDbPagedResponse(page: resp.page, results: fixed, totalPages: resp.totalPages, totalResults: resp.totalResults)
    }

    private func request<T: Decodable>(path: String, items: [URLQueryItem]) async throws -> T {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = items.isEmpty ? nil : items
        
        guard let url = comps.url else { throw TMDbError.badURL }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, resp) = try await session.data(for: request)
        
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw TMDbError.http((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
}
