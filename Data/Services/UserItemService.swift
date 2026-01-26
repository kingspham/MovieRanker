// UserItemService.swift
// Simple cloud sync for watchlist, seen, and favorites

import Foundation
import Supabase
import SwiftData

@MainActor
class UserItemService {
    static let shared = UserItemService()
    private init() {}
    
    // MARK: - Upload to Cloud
    
    /// Upload a single UserItem to cloud (watchlist, seen, favorite)
    func uploadUserItem(_ item: UserItem, movie: Movie) async {
        guard let client = AuthService.shared.client else {
            print("❌ No Supabase client")
            return
        }
        
        guard let user = try? await client.auth.session.user else {
            print("❌ No authenticated user")
            return
        }
        
        let dto = UserItemDTO(
            id: item.id,
            user_id: user.id,
            movie_id: movie.id,
            tmdb_id: movie.tmdbID,
            title: movie.title,
            poster_path: movie.posterPath,
            media_type: movie.mediaType,
            state: item.state.rawValue,
            created_at: item.createdAt
        )
        
        do {
            try await client.from("user_items")
                .upsert(dto)
                .execute()
            print("✅ Uploaded user item: \(movie.title) - State: \(item.state.rawValue)")
        } catch {
            print("❌ Upload Error: \(error)")
        }
    }
}

// MARK: - Data Transfer Object

struct UserItemDTO: Codable {
    let id: UUID
    let user_id: UUID
    let movie_id: UUID
    let tmdb_id: Int?
    let title: String
    let poster_path: String?
    let media_type: String
    let state: String // "seen", "watchlist", "favorite"
    let created_at: Date
}
