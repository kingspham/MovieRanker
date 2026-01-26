// SyncManager.swift
// Simple coordinator for cloud sync operations

import Foundation
import SwiftData

@MainActor
class SyncManager {
    static let shared = SyncManager()
    private init() {}
    
    /// Upload watchlist addition
    func syncWatchlistAdd(movie: Movie, item: UserItem) async {
        await UserItemService.shared.uploadUserItem(item, movie: movie)
    }
    
    /// Upload seen status
    func syncSeenStatus(movie: Movie, item: UserItem) async {
        await UserItemService.shared.uploadUserItem(item, movie: movie)
    }
    
    /// Upload custom list
    func syncList(list: CustomList) async {
        await ListService.shared.uploadList(list)
    }
    
    /// Upload a rating (requires ScoreService)
    func syncNewRating(movie: Movie, score: Score) async {
        await ScoreService.shared.uploadScore(score, movie: movie)
    }
}
