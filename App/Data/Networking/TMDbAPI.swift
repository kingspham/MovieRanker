//
//  TMDbAPI.swift
//  MovieRanker
//

import Foundation

// Keep old call sites working: many views use `TMDbMovie`
public typealias TMDbMovie = TMDbMovieSummary

// MARK: - Public DTOs (not @MainActor)

public struct TMDbMovieSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let overview: String?
    public let releaseDate: String?
    public let posterPath: String?

    public var year: Int? {
        guard let s = releaseDate, s.count >= 4, let y = Int(s.prefix(4)) else { return nil }
        return y
    }
    
    public var genreIDs: [Int] { [] }
    public var popularity: Double? { nil }

    private enum CodingKeys: String, CodingKey {
        case id, title, overview
        case releaseDate = "release_date"
        case posterPath  = "poster_path"
    }
}

public struct TMDbPagedResponse<T: Codable & Sendable>: Codable, Sendable {
    public let page: Int
    public let results: [T]
    public let totalPages: Int?
    public let totalResults: Int?

    private enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }

    public init(page: Int, results: [T], totalPages: Int?, totalResults: Int?) {
        self.page = page
        self.results = results
        self.totalPages = totalPages
        self.totalResults = totalResults
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.page = (try? c.decode(Int.self, forKey: .page)) ?? 1
        self.results = (try? c.decode([T].self, forKey: .results)) ?? []
        self.totalPages = try? c.decode(Int.self, forKey: .totalPages)
        self.totalResults = try? c.decode(Int.self, forKey: .totalResults)
    }
}

// MARK: - Errors

public enum TMDbError: Error, LocalizedError {
    case missingAPIKey
    case badURL
    case http(Int)
    case decoding(Error)
    case transport(Error)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:         return "TMDb API key is missing."
        case .badURL:                return "Could not build TMDb URL."
        case .http(let c):           return "TMDb HTTP error \(c)."
        case .decoding(let e):       return "TMDb decoding failed: \(e.localizedDescription)"
        case .transport(let e):      return "Network error: \(e.localizedDescription)"
        }
    }
}

// MARK: - Client (actor)

public actor TMDbClient {
    private let apiKey: String
    private let base = URL(string: "https://api.themoviedb.org/3")!
    private let session: URLSession

    // Shared singleton
    public static let shared: TMDbClient = {
        try! TMDbClient()
    }()

    public init(session: URLSession = .shared) throws {
        guard
            let key = Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String,
            key.isEmpty == false
        else { throw TMDbError.missingAPIKey }
        self.apiKey = key
        self.session = session
    }

    // Build image URL (for Poster components)
    public nonisolated static func makeImageURL(path: String?, size: ImageSize) -> URL? {
        guard var p = path, !p.isEmpty else { return nil }
        // If TMDb returns a full URL (rare, but be defensive), just use it.
        if let url = URL(string: p), url.scheme != nil { return url }
        // TMDb poster paths usually start with "/". Add it if missing.
        if p.first != "/" { p = "/" + p }
        return URL(string: "https://image.tmdb.org/t/p/\(size.rawValue)\(p)")
    }

    public enum ImageSize: String {
        case w185, w342, original
    }

    // MARK: - Search / Popular

    public func search(query: String, page: Int = 1) async throws -> [TMDbMovieSummary] {
        let result: TMDbPagedResponse<TMDbMovieSummary> = try await request(
            path: "/search/movie",
            items: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "language", value: "en-US"),
                URLQueryItem(name: "include_adult", value: "false")
            ]
        )
        return result.results
    }

    public func searchMovies(query: String, page: Int = 1, language: String = "en-US")
    async throws -> TMDbPagedResponse<TMDbMovieSummary> {
        try await request(
            path: "/search/movie",
            items: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "include_adult", value: "false")
            ]
        )
    }

    public func searchShows(query: String, page: Int = 1) async throws -> [TMDbShow] {
        let result: TMDbPagedResponse<TMDbShow> = try await request(
            path: "/search/tv",
            items: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "language", value: "en-US"),
                URLQueryItem(name: "include_adult", value: "false")
            ]
        )
        return result.results
    }

    public func popularMovies(page: Int = 1, language: String = "en-US")
    async throws -> TMDbPagedResponse<TMDbMovieSummary> {
        try await request(
            path: "/movie/popular",
            items: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "language", value: language)
            ]
        )
    }
    
    public func popularShows(page: Int = 1, language: String = "en-US")
    async throws -> TMDbPagedResponse<TMDbShow> {
        try await request(
            path: "/tv/popular",
            items: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "language", value: language)
            ]
        )
    }
    
    public func discoverMovies(genreIDs: [Int], page: Int = 1, language: String = "en-US")
    async throws -> TMDbPagedResponse<TMDbMovieSummary> {
        let withGenres = genreIDs.map(String.init).joined(separator: ",")
        return try await request(
            path: "/discover/movie",
            items: [
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "sort_by", value: "popularity.desc"),
                URLQueryItem(name: "include_adult", value: "false"),
                URLQueryItem(name: "with_genres", value: withGenres),
                URLQueryItem(name: "page", value: String(page))
            ]
        )
    }

    // MARK: - NEW: Browse endpoints (used by HomeView)

    public func nowPlaying(region: String = "US", page: Int = 1, language: String = "en-US")
    async throws -> TMDbPagedResponse<TMDbMovieSummary> {
        try await request(
            path: "/movie/now_playing",
            items: [
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "region", value: region),
                URLQueryItem(name: "page", value: String(page))
            ]
        )
    }

    public func upcoming(region: String = "US", page: Int = 1, language: String = "en-US")
    async throws -> TMDbPagedResponse<TMDbMovieSummary> {
        try await request(
            path: "/movie/upcoming",
            items: [
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "region", value: region),
                URLQueryItem(name: "page", value: String(page))
            ]
        )
    }

    public func streamingNow(providers: [Int], region: String = "US", page: Int = 1, language: String = "en-US")
    async throws -> TMDbPagedResponse<TMDbMovieSummary> {
        let providerCSV = providers.map(String.init).joined(separator: ",")
        return try await request(
            path: "/discover/movie",
            items: [
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "region", value: region),
                URLQueryItem(name: "sort_by", value: "popularity.desc"),
                URLQueryItem(name: "include_adult", value: "false"),
                URLQueryItem(name: "with_watch_providers", value: providerCSV),
                URLQueryItem(name: "watch_region", value: region),
                URLQueryItem(name: "page", value: String(page))
            ]
        )
    }

    // MARK: - Debug logging helpers
    private nonisolated static func debugLogHTTPError(path: String, url: URL, status: Int, data: Data?) {
#if DEBUG
        if let d = data {
            let payload = String(data: d, encoding: .utf8) ?? "<non-UTF8 data: \(d.count) bytes>"
            print("TMDb HTTP error for \(path) [status: \(status)]:\nURL: \(url.absoluteString)\nPayload:\n\(payload)")
        } else {
            print("TMDb HTTP error for \(path) [status: \(status)]\nURL: \(url.absoluteString)")
        }
#endif
    }

    private nonisolated static func debugLogDecodingError(path: String, message: String, data: Data?) {
#if DEBUG
        if let d = data {
            let payload = String(data: d, encoding: .utf8) ?? "<non-UTF8 data: \(d.count) bytes>"
            print("TMDb decoding failed for \(path): \(message)\nPayload:\n\(payload)")
        } else {
            print("TMDb decoding failed for \(path): \(message)")
        }
#endif
    }

    // MARK: - Core request

    private func request<T: Decodable>(path: String, items: [URLQueryItem]) async throws -> T {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var q = items
        q.append(URLQueryItem(name: "api_key", value: apiKey))
        comps.queryItems = q
        guard let url = comps.url else { throw TMDbError.badURL }

        var req = URLRequest(url: url)
        req.cachePolicy = .returnCacheDataElseLoad

        var lastData: Data? = nil

        do {
            let (data, resp) = try await session.data(for: req)
            lastData = data
            guard let http = resp as? HTTPURLResponse else { throw TMDbError.http(-1) }
            guard (200..<300).contains(http.statusCode) else { throw TMDbError.http(http.statusCode) }

            let dec = JSONDecoder()
            dec.keyDecodingStrategy = .convertFromSnakeCase
            return try dec.decode(T.self, from: data)
        } catch TMDbError.http(let code) {
            TMDbClient.debugLogHTTPError(path: path, url: url, status: code, data: lastData)
            throw TMDbError.http(code)
        } catch let decErr as DecodingError {
            // Build a more descriptive decoding error message
            let message: String
            switch decErr {
            case .keyNotFound(let key, let ctx):
                message = "Key not found: \(key.stringValue) at \(ctx.codingPath.map{ $0.stringValue }.joined(separator: "."))"
            case .typeMismatch(let type, let ctx):
                message = "Type mismatch for \(type) at \(ctx.codingPath.map{ $0.stringValue }.joined(separator: "."))"
            case .valueNotFound(let type, let ctx):
                message = "Value not found for \(type) at \(ctx.codingPath.map{ $0.stringValue }.joined(separator: "."))"
            case .dataCorrupted(let ctx):
                message = "Data corrupted: \(ctx.debugDescription)"
            @unknown default:
                message = "Unknown decoding error"
            }
            TMDbClient.debugLogDecodingError(path: path, message: message, data: lastData)
            throw TMDbError.decoding(NSError(domain: "TMDbDecoding", code: 0, userInfo: [NSLocalizedDescriptionKey: message]))
        } catch let e as TMDbError {
            throw e
        } catch {
            if (error as NSError).domain == NSURLErrorDomain { throw TMDbError.transport(error) }
            throw TMDbError.decoding(error)
        }
    }
}

