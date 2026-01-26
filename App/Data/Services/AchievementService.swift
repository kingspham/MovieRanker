//
//  AchievementService.swift
//  MovieRanker
//

import Foundation
import SwiftData

enum AchievementService {
    /// Checks all relevant models and unlocks new achievements for the current user.
    @MainActor static func checkAndUnlock(context: ModelContext) {
        guard let owner = SessionManager.shared.userId else { return }

        let items: [UserItem]        = context.fetchAll()
        let logs: [LogEntry]         = context.fetchAll()
        let scores: [Score]          = context.fetchAll()
        let achievements: [Achievement] = context.fetchAll()

        var newOnes: [Achievement] = []

        func already(_ key: String) -> Bool {
            achievements.contains { $0.key == key }
        }

        // MARK: Watched milestones
        let watchedCount = items.filter { $0.state == .seen }.count
        if watchedCount >= 10 && !already("watched_10") {
            newOnes.append(Achievement(ownerId: owner,
                key: "watched_10",
                title: "Cinephile in Training",
                detail: "You’ve watched 10 movies!",
                icon: "film"))
        }
        if watchedCount >= 50 && !already("watched_50") {
            newOnes.append(Achievement(ownerId: owner,
                key: "watched_50",
                title: "Movie Marathoner",
                detail: "50 movies logged — impressive stamina.",
                icon: "flame"))
        }

        // MARK: Ranking milestones
        let rankEvents = logs.filter { ($0.labels ?? []).contains("rank") }.count
        if rankEvents >= 10 && !already("rank_10") {
            newOnes.append(Achievement(ownerId: owner,
                key: "rank_10",
                title: "First Rankings",
                detail: "Completed 10 ranking rounds.",
                icon: "trophy"))
        }

        // MARK: Friend tags
        func normalizeWithWho(_ value: Any?) -> [String] {
            switch value {
            case let array as [String]:
                return array
            case let string as String:
                return string
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            default:
                return []
            }
        }

        let tags: [String] = logs.flatMap { normalizeWithWho($0.withWho) }

        if tags.count >= 5 && !already("friends_5") {
            newOnes.append(Achievement(ownerId: owner,
                key: "friends_5",
                title: "Social Watcher",
                detail: "Tagged friends in 5+ watch logs.",
                icon: "person.2.fill"))
        }

        // MARK: Top 10% Elo (local check)
        let sorted = scores.sorted { $0.display100 > $1.display100 }
        if let top = sorted.first, top.display100 >= 90, !already("elo_90") {
            newOnes.append(Achievement(ownerId: owner,
                key: "elo_90",
                title: "Elite Taster",
                detail: "You’re among the top scorers!",
                icon: "star.fill"))
        }

        // MARK: Save new achievements
        for a in newOnes { context.insert(a) }
        if !newOnes.isEmpty { SD.save(context) }
    }
}

