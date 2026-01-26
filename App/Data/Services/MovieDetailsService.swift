import Foundation

// MARK: - Types exposed to UI

struct MovieDetails: Sendable {
    struct Cast: Sendable, Identifiable {
        let id: Int
        let name: String
        let character: String?
        let profilePath: String?
    }

    let id: Int
    let title: String
    let year: Int?
    let overview: String?
    let runtimeMinutes: Int?
    let genres: [String]
    let cast: [Cast]
    /// Where to watch by provider name (e.g. “Netflix”, “HBO Max”, …)
    let providersFlatrate: [String]
    let providersRent: [String]
    let providersBuy: [String]

    /// External ratings (all optional)
    let imdbRating: String?
    let rottenTomatoes: String?
    let metacritic: String?
}

// MARK: - Service

enum MovieDetailsService {

    private static var tmdbKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String) ?? ""
    }

    private static var omdbKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "OMDB_API_KEY") as? String) ?? ""
    }

    /// Fetch rich details from TMDb and merge OMDb ratings (IMDb/RT/MC).
    static func fetch(for tmdb: TMDbMovie, region: String = "US") async throws -> MovieDetails {
        guard !tmdbKey.isEmpty else { throw URLError(.userAuthenticationRequired) }

        var comps = URLComponents(string: "https://api.themoviedb.org/3/movie/\(tmdb.id)")!
        comps.queryItems = [
            .init(name: "api_key", value: tmdbKey),
            .init(name: "language", value: "en-US"),
            .init(name: "append_to_response", value: "credits,watch/providers,external_ids")
        ]

        let url = comps.url!
        let cacheKey = "tmdb.movie.\(tmdb.id)"

        let data: Data
        if let cached = await APICache.shared.get(cacheKey) {
            data = cached
        } else {
            let (d, resp) = try await URLSession.shared.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            await APICache.shared.set(cacheKey, data: d, ttl: 60 * 60 * 6) // 6h
            data = d
        }

        // Decode TMDb payload (only fields we use)
        let root = try JSONDecoder().decode(TMDbMovieDetailsDTO.self, from: data)

        // Watch providers for region
        let prov = root.watch_providers?.results?[region]
        let namesFlat = (prov?.flatrate ?? []).map { $0.provider_name }
        let namesRent = (prov?.rent ?? []).map { $0.provider_name }
        let namesBuy  = (prov?.buy  ?? []).map { $0.provider_name }

        // External IDs -> IMDb id for OMDb
        var imdbRating: String? = nil
        var rt: String? = nil
        var mc: String? = nil

        if let imdb = root.external_ids?.imdb_id, !imdb.isEmpty, !omdbKey.isEmpty {
            do {
                let r = try await fetchOMDb(imdbID: imdb)
                imdbRating = r.imdb
                rt = r.rt
                mc = r.mc
            } catch {
                // keep TMDb data even if OMDb fails
            }
        } else if !omdbKey.isEmpty {
            // fallback by title/year (less precise)
            let fallbackYear: Int? = {
                guard let s = root.release_date, s.count >= 4 else { return nil }
                return Int(String(s.prefix(4)))
            }()
            do {
                let r = try await fetchOMDb(title: root.title, year: fallbackYear)
                imdbRating = r.imdb
                rt = r.rt
                mc = r.mc
            } catch {
                // ignore
            }
        }

        let cast = (root.credits?.cast ?? [])
            .prefix(12)
            .map { MovieDetails.Cast(id: $0.id, name: $0.name, character: $0.character, profilePath: $0.profile_path) }

        // Year from release_date safely
        let year: Int? = {
            guard let s = root.release_date, s.count >= 4 else { return nil }
            return Int(String(s.prefix(4)))
        }()

        return MovieDetails(
            id: root.id,
            title: root.title,
            year: year,
            overview: root.overview,
            runtimeMinutes: root.runtime,           // TMDb returns runtime in minutes (Int?)
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

    // MARK: OMDb

    private static func fetchOMDb(imdbID: String) async throws -> (imdb: String?, rt: String?, mc: String?) {
        guard !omdbKey.isEmpty else { return (nil, nil, nil) }
        var comps = URLComponents(string: "https://www.omdbapi.com/")!
        comps.queryItems = [
            .init(name: "apikey", value: omdbKey),
            .init(name: "i", value: imdbID)
        ]
        return try await decodeOMDb(from: comps.url!)
    }

    private static func fetchOMDb(title: String, year: Int?) async throws -> (imdb: String?, rt: String?, mc: String?) {
        guard !omdbKey.isEmpty else { return (nil, nil, nil) }
        var comps = URLComponents(string: "https://www.omdbapi.com/")!
        var items = [URLQueryItem(name: "apikey", value: omdbKey),
                     URLQueryItem(name: "t", value: title)]
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
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
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

private struct TMDbMovieDetailsDTO: Decodable {
    struct Genre: Decodable { let id: Int; let name: String }
    struct CastDTO: Decodable { let id: Int; let name: String; let character: String?; let profile_path: String? }
    struct Credits: Decodable { let cast: [CastDTO]? }
    struct ExternalIDs: Decodable { let imdb_id: String? }

    struct ProviderItem: Decodable { let provider_id: Int; let provider_name: String }
    struct ProviderRegion: Decodable {
        let flatrate: [ProviderItem]?
        let rent: [ProviderItem]?
        let buy: [ProviderItem]?
    }
    struct WatchProviders: Decodable { let results: [String: ProviderRegion]? }

    let id: Int
    let title: String
    let overview: String?
    let runtime: Int?
    let release_date: String?
    let genres: [Genre]
    let credits: Credits?
    let external_ids: ExternalIDs?
    let watch_providers: WatchProviders?

    private enum CodingKeys: String, CodingKey {
        case id, title, overview, runtime, genres, credits, external_ids
        case watch_providers
        case release_date
    }
}
