import Foundation

public struct TMDbShow: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let title: String  // "name" in API, but we'll map it
    public let overview: String?
    public let firstAirDate: String?
    public let posterPath: String?
    public let genreIDs: [Int]
    public let popularity: Double?

    public var year: Int? {
        guard let s = firstAirDate, s.count >= 4, let y = Int(s.prefix(4)) else { return nil }
        return y
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title = "name"  // TMDb uses "name" for TV shows
        case overview
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case genreIDs = "genre_ids"
        case popularity
    }

    public init(id: Int, title: String, overview: String?, firstAirDate: String?, posterPath: String?, genreIDs: [Int], popularity: Double?) {
        self.id = id
        self.title = title
        self.overview = overview
        self.firstAirDate = firstAirDate
        self.posterPath = posterPath
        self.genreIDs = genreIDs
        self.popularity = popularity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.title = (try? c.decode(String.self, forKey: .title)) ?? ""
        self.overview = try? c.decode(String.self, forKey: .overview)
        self.firstAirDate = try? c.decode(String.self, forKey: .firstAirDate)
        self.posterPath = try? c.decode(String.self, forKey: .posterPath)
        self.genreIDs = (try? c.decode([Int].self, forKey: .genreIDs)) ?? []
        self.popularity = try? c.decode(Double.self, forKey: .popularity)
    }
}
