import Foundation

struct TMDbMovieSummary: Decodable, Identifiable {
    let id: Int
    let title: String
    let releaseDate: String?
    let posterPath: String?

    var year: Int? {
        guard let d = releaseDate, d.count >= 4, let y = Int(d.prefix(4)) else { return nil }
        return y
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case releaseDate = "release_date"
        case posterPath  = "poster_path"
    }
}

struct TMDbSearchResponse: Decodable {
    let results: [TMDbMovieSummary]
}

enum TMDbError: Error, LocalizedError {
    case missingAPIKey
    case badURL
    case server(String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "TMDB_API_KEY not found in Info.plist"
        case .badURL: return "Invalid TMDb URL"
        case .server(let s): return s
        case .decoding(let e): return "Decoding failed: \(e.localizedDescription)"
        }
    }
}

final class TMDbClient {
    private let apiKey: String
    private let session: URLSession
    private let imageBase: String

    init?() {
        // 1) Try Info.plist
        let raw = Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY")
        print("[TMDb] TMDB_API_KEY (raw):", raw as Any)
        var key = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // 2) Fallback to environment variable in Debug builds
        #if DEBUG
        if key.isEmpty {
            let env = ProcessInfo.processInfo.environment["TMDB_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !env.isEmpty {
                print("[TMDb] Using TMDB_API_KEY from environment (Debug only)")
                key = env
            }
        }
        #endif

        #if DEBUG
        if key.isEmpty {
            // Final debug-only fallback to unblock local runs.
            let debugToken = "eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiIwMzg1MTE2ZmRmZDVlMGNjNDBhNTU5MDZjMmE3NjJkZiIsIm5iZiI6MTc2MTAxMTcxNC45NjcsInN1YiI6IjY4ZjZlODAyY2NmMDliZTY4MzEwMjE1NSIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.Z-flriebxvPjOcK032l2yfSadJhxULS7nkfMbdWdntk"
            print("[TMDb] Using hardcoded DEBUG token fallback")
            key = debugToken
        }
        #endif

        guard !key.isEmpty else {
            return nil
        }
        self.apiKey = key
        self.session = .shared
        self.imageBase = (Bundle.main.object(forInfoDictionaryKey: "TMDB_IMAGE_BASE") as? String)
            ?? "https://image.tmdb.org/t/p/w185"
    }

    func posterURL(path: String?) -> URL? {
        guard let p = path else { return nil }
        return URL(string: imageBase + p)
    }

    func searchMovies(query: String) async throws -> [TMDbMovieSummary] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { throw TMDbError.badURL }
        guard let url = URL(string: "https://api.themoviedb.org/3/search/movie?query=\(encoded)&include_adult=false&language=en-US&page=1")
        else { throw TMDbError.badURL }

        print("[TMDb] Search URL:", url.absoluteString)

        var req = URLRequest(url: url)
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") // TMDb now prefers Bearer for v4 keys; v3 also accepts ?api_key= but this works widely.
        // If your key is v3 and Bearer fails, switch to:  let url = ... + "&api_key=\(apiKey)"  and remove the Authorization header.

        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw TMDbError.server("HTTP \(http.statusCode)")
        }
        do {
            let decoded = try JSONDecoder().decode(TMDbSearchResponse.self, from: data)
            return decoded.results
        } catch {
            throw TMDbError.decoding(error)
        }
    }
}
