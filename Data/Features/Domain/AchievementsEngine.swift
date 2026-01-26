//
//  AchievementsEngine.swift
//  MovieRanker
//

import Foundation
import SwiftData

// MARK: - Persistent unlock record

/// Stores when a badge was first unlocked so it survives recomputes.
@Model
final class BadgeUnlock {
    @Attribute(.unique) var badgeId: String
    var earnedAt: Date

    init(badgeId: String, earnedAt: Date = .init()) {
        self.badgeId = badgeId
        self.earnedAt = earnedAt
    }
}

/// Optional persistent cache of external critic ratings (e.g., IMDb).
/// Populate this from your MovieInfoView / ShowInfoView after fetching details.
@Model
final class ExternalRatingCache {
    /// TMDb numeric id for the title (movie or show)
    @Attribute(.unique) var tmdbID: Int
    /// IMDb rating on a 0–10 scale (if available)
    var imdbRating: Double?
    var updatedAt: Date

    init(tmdbID: Int, imdbRating: Double?, updatedAt: Date = .init()) {
        self.tmdbID = tmdbID
        self.imdbRating = imdbRating
        self.updatedAt = updatedAt
    }
}

// MARK: - Badge catalog & progress

struct Badge: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    /// Completion target (integer goal, e.g. 10 watched)
    let goal: Int
    /// How to compute current progress from data snapshot.
    let metric: @Sendable (AchievementsSnapshot) -> Int
}

struct BadgeProgress: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let current: Int
    let goal: Int
    let earned: Bool
    let earnedAt: Date?
    var fraction: Double { guard goal > 0 else { return 0 }; return min(1, Double(current) / Double(goal)) }
}

// MARK: - Snapshot of your data (derived from SwiftData)

struct AchievementsSnapshot {
    let totalWatched: Int
    let totalWatchlist: Int
    let consecutiveDays: Int
    let distinctGenresWatched: Int
    let distinctPlatformsUsed: Int
    let friendsTaggedCount: Int

    // New fields for requested badges
    let criticPicksCount: Int      // watched with IMDb ≥ 8.0 (or fallback ≥ 80/100)
    let ninetiesWatchedCount: Int  // watched movies from 1990–1999
}

/// Central engine that (1) builds a snapshot and (2) computes progress for each badge.
/// If a badge just crossed its goal, it writes a `BadgeUnlock`.
enum AchievementsEngine {

    // MARK: Catalog

    static let allBadges: [Badge] = [
        Badge(
            id: "watched_10",
            title: "Starter Critic",
            detail: "Log 10 movies or shows",
            systemImage: "checkmark.circle.fill",
            goal: 10,
            metric: { $0.totalWatched }
        ),
        Badge(
            id: "watched_50",
            title: "Weekend Warrior",
            detail: "Log 50 titles",
            systemImage: "film.stack.fill",
            goal: 50,
            metric: { $0.totalWatched }
        ),
        Badge(
            id: "watched_200",
            title: "Marathoner",
            detail: "Log 200 titles",
            systemImage: "tortoise.fill",
            goal: 200,
            metric: { $0.totalWatched }
        ),
        Badge(
            id: "watchlist_25",
            title: "Planner",
            detail: "Add 25 to Want to Watch",
            systemImage: "bookmark.fill",
            goal: 25,
            metric: { $0.totalWatchlist }
        ),
        Badge(
            id: "streak_7",
            title: "One-Week Streak",
            detail: "Log something 7 days in a row",
            systemImage: "flame.fill",
            goal: 7,
            metric: { $0.consecutiveDays }
        ),
        Badge(
            id: "genres_8",
            title: "Genre Explorer",
            detail: "Watch 8 different genres",
            systemImage: "sparkles",
            goal: 8,
            metric: { $0.distinctGenresWatched }
        ),
        Badge(
            id: "platforms_5",
            title: "Platform Hopper",
            detail: "Watch on 5 different platforms",
            systemImage: "tv.fill",
            goal: 5,
            metric: { $0.distinctPlatformsUsed }
        ),
        Badge(
            id: "with_friends_10",
            title: "Social Viewer",
            detail: "Tag friends on 10 logs",
            systemImage: "person.2.fill",
            goal: 10,
            metric: { $0.friendsTaggedCount }
        ),

        // 🚀 New requested badges:

        Badge(
            id: "critics_choice_10",
            title: "Critic’s Choice",
            detail: "Watch 10 titles rated IMDb 8.0+ (or your score ≥ 80)",
            systemImage: "star.circle.fill",
            goal: 10,
            metric: { $0.criticPicksCount }
        ),
        Badge(
            id: "nineties_kid_20",
            title: "90’s Kid",
            detail: "Watch 20 movies released in 1990–1999",
            systemImage: "clock.fill",
            goal: 20,
            metric: { $0.ninetiesWatchedCount }
        )
    ]

    // MARK: Public API

    @MainActor
    static func computeProgress(context: ModelContext) -> [BadgeProgress] {
        let snapshot = buildSnapshot(context: context)

        // Fetch existing unlocks
        let unlocks: [BadgeUnlock] = (try? context.fetch(FetchDescriptor<BadgeUnlock>())) ?? []
        let unlockById = Dictionary(uniqueKeysWithValues: unlocks.map { ($0.badgeId, $0) })

        var results: [BadgeProgress] = []

        for badge in allBadges {
            let current = badge.metric(snapshot)
            let earnedBefore = unlockById[badge.id]
            let isEarned = current >= badge.goal

            // If newly earned now, persist unlock time
            if isEarned && earnedBefore == nil {
                let rec = BadgeUnlock(badgeId: badge.id, earnedAt: Date())
                context.insert(rec)
                SD.save(context)
                results.append(BadgeProgress(
                    id: badge.id,
                    title: badge.title,
                    detail: badge.detail,
                    systemImage: badge.systemImage,
                    current: current,
                    goal: badge.goal,
                    earned: true,
                    earnedAt: rec.earnedAt
                ))
                continue
            }

            results.append(BadgeProgress(
                id: badge.id,
                title: badge.title,
                detail: badge.detail,
                systemImage: badge.systemImage,
                current: current,
                goal: badge.goal,
                earned: earnedBefore != nil,
                earnedAt: earnedBefore?.earnedAt
            ))
        }

        // Earned first, then by highest fraction
        return results
            .sorted { a, b in
                if a.earned != b.earned { return a.earned && !b.earned }
                if a.fraction == b.fraction { return a.title < b.title }
                return a.fraction > b.fraction
            }
    }

    // MARK: Snapshot builder

    @MainActor
    private static func buildSnapshot(context: ModelContext) -> AchievementsSnapshot {
        let items:   [UserItem]             = (try? context.fetch(FetchDescriptor<UserItem>())) ?? []
        let logs:    [LogEntry]             = (try? context.fetch(FetchDescriptor<LogEntry>())) ?? []
        let movies:  [Movie]                = (try? context.fetch(FetchDescriptor<Movie>())) ?? []
        let scores:  [Score]                = (try? context.fetch(FetchDescriptor<Score>())) ?? []
        let caches:  [ExternalRatingCache]  = (try? context.fetch(FetchDescriptor<ExternalRatingCache>())) ?? []

        // 1) Watched / Watchlist counts
        let totalWatched   = items.filter { $0.state == .seen }.count
        let totalWatchlist = items.filter { $0.state == .watchlist }.count

        // 2) Streak: compute consecutive days with at least one log
        let watchedKeys: [String] = logs.compactMap { $0.watchedOn?.dayKey }
        let createdKeys: [String] = logs.map { $0.createdAt.dayKey }
        let dayKeys: Set<String> = Set(watchedKeys + createdKeys)
        let consecutiveDays = Self.longestRecentStreak(from: dayKeys)

        // 3) Distinct genres from *logged* movies
        let movieIDsWithLogs = Set(logs.compactMap { $0.movie?.id })
        let tastedMovies = movies.filter { movieIDsWithLogs.contains($0.id) }
        let allGenres = tastedMovies.flatMap { $0.safeGenreIDs }
        let distinctGenres = Set(allGenres).count

        // 4) Distinct platforms used (whereWatched on logs)
        let platformKeys: [String] = logs.compactMap { entry in
            guard let raw = entry.whereWatched?.rawValue else { return nil }
            return String(describing: raw)
        }
        let distinctPlatforms: Int = Set<String>(platformKeys).count

        // 5) Friends tagged (how many logs contain at least one friend)
        let friendsTagged: Int = logs.reduce(into: 0) { acc, entry in
            guard let withWho = entry.withWho else { return }
            if AchievementsEngine.hasAnyNames(in: withWho) { acc += 1 }
        }

        // ---- New metrics ----

        // Build helpers
        let scoreByMovieID = Dictionary(uniqueKeysWithValues: scores.map { ($0.movieID, $0.display100) })
        let logsByMovieID: [UUID: [LogEntry]] = logs.reduce(into: [:]) { dict, entry in
            if let m = entry.movie?.id { dict[m, default: []].append(entry) }
        }
        let imdbByTMDbID: [Int: Double] = Dictionary(uniqueKeysWithValues: caches.compactMap { c in
            guard c.tmdbID > 0, let r = c.imdbRating else { return nil }
            return (c.tmdbID, r) // 0–10 scale
        })

        // A) Critic’s Choice: watched titles with IMDb ≥ 8.0 (fallback to ≥ 80/100)
        var criticCount = 0
        for it in items where it.state == .seen {
            guard let m = it.movie else { continue }
            if let tmdb = m.tmdbID, let imdb = imdbByTMDbID[tmdb], imdb >= 8.0 {
                criticCount += 1
            } else if let s = scoreByMovieID[m.id], s >= 80 {
                criticCount += 1
            } else if let arr = logsByMovieID[m.id] {
                let high = arr.compactMap { entry -> Double? in
                    if let i = entry.rating { return Double(i) }
                    if let d = entry.rating { return d <= 10 ? d * 10.0 : d }
                    return nil
                }.max() ?? 0
                if high >= 80 { criticCount += 1 }
            }
        }

        // B) 90’s Kid: watched movies from 1990–1999
        var ninetiesCount = 0
        for it in items where it.state == .seen {
            if let m = it.movie, let y = m.year, (1990...1999).contains(y) {
                ninetiesCount += 1
            }
        }

        return AchievementsSnapshot(
            totalWatched: totalWatched,
            totalWatchlist: totalWatchlist,
            consecutiveDays: consecutiveDays,
            distinctGenresWatched: distinctGenres,
            distinctPlatformsUsed: distinctPlatforms,
            friendsTaggedCount: friendsTagged,
            criticPicksCount: criticCount,
            ninetiesWatchedCount: ninetiesCount
        )
    }

    // MARK: Utilities

    /// Given a set of "yyyy-MM-dd" keys that have activity, count how many consecutive
    /// days up to today (including today) have activity. If today has no activity, streak is 0.
    private static func longestRecentStreak(from activeKeys: Set<String>) -> Int {
        let cal = Calendar(identifier: .iso8601)
        let today = Date()
        let todayKey = today.dayKey
        guard activeKeys.contains(todayKey) else { return 0 }

        var streak = 0
        var d = today
        while activeKeys.contains(d.dayKey) {
            streak += 1
            if let prev = cal.date(byAdding: .day, value: -1, to: d) { d = prev } else { break }
        }
        return streak
    }

    /// Returns true if an arbitrary "withWho" value contains any non-empty name(s).
    /// Accepts [String], [Any] with String elements, or a single String.
    private static func hasAnyNames(in value: Any) -> Bool {
        if let names = value as? [String] {
            return names.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        if let anyArray = value as? [Any] {
            return anyArray.contains { element in
                if let s = element as? String { return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                return false
            }
        }
        if let s = value as? String {
            return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }
}

// MARK: - Shared date helpers

private extension Date {
    var dayKey: String { Date.yyyyMMdd.string(from: self) }
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = .init(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Model conveniences used above

private extension Movie {
    /// Return genre IDs using safe access, avoiding reflection when possible.
    /// This tries common shapes: [Int], [Int?], Optional wrappers, or [Any] coercible to Int.
    var safeGenreIDs: [Int] {
        // If your Movie exposes `genreIDs` directly (e.g., `let genreIDs: [Int]?`), prefer accessing it directly.
        // The following reflection fallback keeps this engine decoupled from your exact schema.
        let mirror = Mirror(reflecting: self)
        for child in mirror.children {
            guard child.label == "genreIDs" else { continue }
            if let ids = child.value as? [Int] { return ids }
            if let optionalIds = child.value as? [Int?] { return optionalIds.compactMap { $0 } }
            if let anyArray = child.value as? [Any] {
                return anyArray.compactMap { element in
                    if let i = element as? Int { return i }
                    if let n = element as? NSNumber { return n.intValue }
                    return nil
                }
            }
            // Optional wrapper via Mirror
            let optMirror = Mirror(reflecting: child.value)
            if optMirror.displayStyle == .optional, let someChild = optMirror.children.first?.value {
                if let ids = someChild as? [Int] { return ids }
                if let optionalIds = someChild as? [Int?] { return optionalIds.compactMap { $0 } }
                if let anyArray = someChild as? [Any] {
                    return anyArray.compactMap { element in
                        if let i = element as? Int { return i }
                        if let n = element as? NSNumber { return n.intValue }
                        return nil
                    }
                }
            }
        }
        return []
    }
}
