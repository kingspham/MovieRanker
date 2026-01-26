// UserItemService.swift
// Cloud sync for watchlist, seen, and favorites

import Foundation
import Supabase
import SwiftData

// Local representation of user item states used for syncing
enum UserItemState: String, Codable, CaseIterable {
    case watchlist
    case seen
    case favorite
}

extension UserItem.State {
    init(from serviceState: UserItemState) {
        switch serviceState {
        case .watchlist: self = .watchlist
        case .seen: self = .seen
        case .favorite: self = .favorite
        }
    }
}

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

    // MARK: - Sync from Cloud

    /// Fetch all user items from cloud
    func fetchAllUserItems() async -> [UserItemDTO] {
        guard let client = AuthService.shared.client,
              let user = try? await client.auth.session.user else {
            print("❌ No auth for fetching user items")
            return []
        }

        do {
            let response: [UserItemDTO] = try await client
                .from("user_items")
                .select()
                .eq("user_id", value: user.id)
                .execute()
                .value
            print("✅ Fetched \(response.count) user items from cloud")
            return response
        } catch {
            print("❌ Error fetching user items: \(error)")
            return []
        }
    }

    /// Sync user items from cloud to local database
    func syncUserItems(context: ModelContext) async {
        let cloudItems = await fetchAllUserItems()

        guard !cloudItems.isEmpty else {
            print("ℹ️ No cloud user items to sync")
            return
        }

        var syncedCount = 0

        // Fetch all local user items and movies
        let allLocalItems = (try? context.fetch(FetchDescriptor<UserItem>())) ?? []
        let allMovies = (try? context.fetch(FetchDescriptor<Movie>())) ?? []

        for cloudItem in cloudItems {
            // Check if we already have this item locally
            if allLocalItems.contains(where: { $0.id == cloudItem.id }) {
                continue // Already exists
            }

            // Find or create the movie
            var movie: Movie
            if let existingMovie = allMovies.first(where: { $0.id == cloudItem.movie_id }) {
                movie = existingMovie
            } else {
                // Create a minimal movie record
                movie = Movie(
                    title: cloudItem.title,
                    year: nil,
                    tmdbID: cloudItem.tmdb_id,
                    posterPath: cloudItem.poster_path,
                    mediaType: cloudItem.media_type
                )
                movie.id = cloudItem.movie_id
                context.insert(movie)
            }

            // Create the user item
            let state = UserItemState(rawValue: cloudItem.state) ?? .watchlist
            let newItem = UserItem(movie: movie, state: UserItem.State(from: state), ownerId: cloudItem.user_id.uuidString)
            context.insert(newItem)
            syncedCount += 1
        }

        do {
            try context.save()
            print("✅ Synced \(syncedCount) user items from cloud")
        } catch {
            print("❌ Error saving synced user items: \(error)")
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

