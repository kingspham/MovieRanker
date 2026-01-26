import Foundation

// MARK: - Types exposed to UI

struct RichShowDetails: Sendable {
    struct Cast: Sendable, Identifiable {
        let id: Int
        let name: String
        let character: String?
        let profilePath: String?
    }

    let id: Int
    let name: String
    let yearStart: Int?
    let overview: String?
    let seasons: Int?
    let episodes: Int?
    let genres: [String]
    let cast: [Cast]
    // Where to watch “now”
    let providersFlatrate: [String]
    let providersRent: [String]
    let providersBuy: [String]

    // External ratings (best-effort for series via OMDb)
    let imdbRating: String?
    let rottenTomatoes: String?
    let metacritic: String?
}

// MARK: - Service

enum ShowDetailsService {

    private static var tmdbKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String) ?? ""
    }

    private static var omdbKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "OMDB_API_KEY") as? String) ?? ""
    }

    /// Fetch rich details for a TMDb TV show id and merge OMDb series ratings if available.
    static func fetch(showID: Int, titleForFallback: String? = nil, yearForFallback: Int? = nil, region: String = "US") async throws -> RichShowDetails {
        guard !tmdbKey.isEmpty else { throw URLError(.userAuthenticationRequired) }

        var comps = URLComponents(string: "https://api.themoviedb.org/3/tv/\(showID)")!
        comps.queryItems = [
            .init(name: "api_key", value: tmdbKey),
            .init(name: "language", value: "en-US"),
            // aggregate_credits groups roles across seasons; better for top-cast
            .init(name: "append_to_response", value: "aggregate_credits,watch/providers,external_ids")
        ]

        let url = comps.url!
        let cacheKey = "tmdb.tv.\(showID)"
        let data: Data
        if let cached = await APICache.shared.get(cacheKey) {
            data = cached
        } else {
            let (d, resp) = try await URLSession.shared.data(from: url)
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
            await APICache.shared.set(cacheKey, data: d, ttl: 60 * 60 * 6) // 6h
            data = d
        }

        let root = try JSONDecoder().decode(TMDbShowDetailsDTO.self, from: data)

        // Providers for region
        let prov = root.watch_providers?.results?[region]
        let namesFlat = (prov?.flatrate ?? []).map { $0.provider_name }
        let namesRent = (prov?.rent ?? []).map { $0.provider_name }
        let namesBuy  = (prov?.buy  ?? []).map { $0.provider_name }

        // External ratings via OMDb (series)
        var imdbRating: String? = nil
        var rt: String? = nil
        var mc: String? = nil

        if let imdb = root.external_ids?.imdb_id, !imdb.isEmpty, !omdbKey.isEmpty {
            do {
                let r = try await fetchOMDbSeries(imdbID: imdb)
                imdbRating = r.imdb; rt = r.rt; mc = r.mc
            } catch { }
        } else if !omdbKey.isEmpty {
            do {
                let r = try await fetchOMDbSeries(title: titleForFallback ?? root.name, year: yearForFallback)
                imdbRating = r.imdb; rt = r.rt; mc = r.mc
            } catch { }
        }

        // Cast (top 12)
        let cast = (root.aggregate_credits?.cast ?? [])
            .prefix(12)
            .map { RichShowDetails.Cast(id: $0.id, name: $0.name, character: $0.roles?.first?.character, profilePath: $0.profile_path) }

        // Year start
        let yStart = root.first_air_date.flatMap { $0.count >= 4 ? Int($0.prefix(4)) : nil }

        return RichShowDetails(
            id: root.id,
            name: root.name,
            yearStart: yStart,
            overview: root.overview,
            seasons: root.number_of_seasons,
            episodes: root.number_of_episodes,
            genres: root.genres.map { $0.name },
            cast: cast,
            providersFlatrate: namesFlat,
            providersRent: namesRent,
            providersBuy: namesBuy,
            imdbRating: imdbRating,
            rottenTomatoes: rt,
            metacritic: mc
        )
    }

    // MARK: OMDb (series)

    private static func fetchOMDbSeries(imdbID: String) async throws -> (imdb: String?, rt: String?, mc: String?) {
        guard !omdbKey.isEmpty else { return (nil, nil, nil) }
        var comps = URLComponents(string: "https://www.omdbapi.com/")!
        comps.queryItems = [.init(name: "apikey", value: omdbKey),
                            .init(name: "i", value: imdbID),
                            .init(name: "type", value: "series")]
        return try await decodeOMDb(from: comps.url!)
    }

    private static func fetchOMDbSeries(title: String, year: Int?) async throws -> (imdb: String?, rt: String?, mc: String?) {
        guard !omdbKey.isEmpty else { return (nil, nil, nil) }
        var comps = URLComponents(string: "https://www.omdbapi.com/")!
        var items = [URLQueryItem(name: "apikey", value: omdbKey),
                     URLQueryItem(name: "t", value: title),
                     URLQueryItem(name: "type", value: "series")]
        if let y = year { items.append(.init(name: "y", value: String(y))) }
        comps.queryItems = items
        return try await decodeOMDb(from: comps.url!)
    }

    private static func decodeOMDb(from url: URL) async throws -> (imdb: String?, rt: String?, mc: String?) {
        let key = "omdb.\(url.absoluteString)"
        let data: Data
        if let cached = await APICache.shared.get(key) {
            data = cached
        } else {
            let (d, resp) = try await URLSession.shared.data(from: url)
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
            await APICache.shared.set(key, data: d, ttl: 60 * 60 * 24) // 24h
            data = d
        }
        struct OMDb: Decodable {
            struct R: Decodable { let Source: String; let Value: String }
            let imdbRating: String?
            let Ratings: [R]?
        }
        let decoded = try JSONDecoder().decode(OMDb.self, from: data)
        var imdb = decoded.imdbRating
        var rt: String? = nil
        var mc: String? = nil
        for r in decoded.Ratings ?? [] {
            switch r.Source.lowercased() {
            case "rotten tomatoes": rt = r.Value
            case "metacritic": mc = r.Value
            case "internet movie database": imdb = imdb ?? r.Value
            default: break
            }
        }
        return (imdb, rt, mc)
    }
}

// MARK: - TMDb DTOs (subset)

private struct TMDbShowDetailsDTO: Decodable {
    struct Genre: Decodable { let id: Int; let name: String }

    struct Role: Decodable { let character: String? }
    struct CastDTO: Decodable {
        let id: Int
        let name: String
        let profile_path: String?
        let roles: [Role]?
    }
    struct AggregateCredits: Decodable { let cast: [CastDTO]? }

    struct ExternalIDs: Decodable { let imdb_id: String? }

    struct ProviderItem: Decodable { let provider_id: Int; let provider_name: String }
    struct ProviderRegion: Decodable {
        let flatrate: [ProviderItem]?
        let rent: [ProviderItem]?
        let buy: [ProviderItem]?
    }
    struct WatchProviders: Decodable { let results: [String: ProviderRegion]? }

    let id: Int
    let name: String
    let overview: String?
    let first_air_date: String?
    let number_of_seasons: Int?
    let number_of_episodes: Int?
    let genres: [Genre]
    let aggregate_credits: AggregateCredits?
    let external_ids: ExternalIDs?
    let watch_providers: WatchProviders?

    private enum CodingKeys: String, CodingKey {
        case id, name, overview, genres
        case first_air_date, number_of_seasons, number_of_episodes
        case aggregate_credits, external_ids, watch_providers
    }
}
