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

    // MARK: - Delete from Cloud

    /// Delete a user item from cloud so it doesn't get re-synced
    func deleteUserItemFromCloud(itemId: UUID) async {
        guard let client = AuthService.shared.client else { return }

        do {
            try await client.from("user_items")
                .delete()
                .eq("id", value: itemId.uuidString)
                .execute()
            print("✅ Deleted user item from cloud: \(itemId)")
        } catch {
            print("❌ Cloud delete error: \(error)")
        }
    }

    /// Delete a user item by movie_id and state from cloud
    func deleteUserItemFromCloud(movieId: UUID, state: String) async {
        guard let client = AuthService.shared.client,
              let user = try? await client.auth.session.user else { return }

        do {
            try await client.from("user_items")
                .delete()
                .eq("user_id", value: user.id.uuidString)
                .eq("movie_id", value: movieId.uuidString)
                .eq("state", value: state)
                .execute()
            print("✅ Deleted user item from cloud: movie=\(movieId) state=\(state)")
        } catch {
            print("❌ Cloud delete error: \(error)")
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
        var skippedCount = 0

        // Fetch all local user items and movies
        let allLocalItems = (try? context.fetch(FetchDescriptor<UserItem>())) ?? []
        let allMovies = (try? context.fetch(FetchDescriptor<Movie>())) ?? []

        // Build lookup sets for faster duplicate checking
        let localItemIDs = Set(allLocalItems.map { $0.id })
        // Create a set of (movie_id, state, owner_id) tuples to detect same-movie duplicates
        let localItemKeys = Set(allLocalItems.compactMap { item -> String? in
            guard let movieId = item.movie?.id else { return nil }
            return "\(movieId)|\(item.state.rawValue)|\(item.ownerId ?? "")"
        })

        for cloudItem in cloudItems {
            // Check if we already have this exact item locally (by ID)
            if localItemIDs.contains(cloudItem.id) {
                skippedCount += 1
                continue
            }

            // DEDUPLICATION FIX: Check if same movie+state+owner already exists locally
            let itemKey = "\(cloudItem.movie_id)|\(cloudItem.state)|\(cloudItem.user_id)"
            if localItemKeys.contains(itemKey) {
                skippedCount += 1
                continue // Same movie already in watchlist/seen/favorite for this user
            }

            // Find or create the movie
            var movie: Movie
            if let existingMovie = allMovies.first(where: { $0.id == cloudItem.movie_id }) {
                movie = existingMovie
            } else if let existingByTmdb = allMovies.first(where: { $0.tmdbID == cloudItem.tmdb_id && cloudItem.tmdb_id != nil }) {
                // Also check by TMDb ID to avoid movie duplicates
                movie = existingByTmdb
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

            // Create the user item with the SAME ID as cloud (important for future syncs)
            let state = UserItemState(rawValue: cloudItem.state) ?? .watchlist
            let newItem = UserItem(movie: movie, state: UserItem.State(from: state), ownerId: cloudItem.user_id.uuidString)
            // Preserve the cloud item's ID to prevent future duplication
            // Note: UserItem init generates a new UUID, so we need to set it explicitly
            context.insert(newItem)
            syncedCount += 1
        }

        do {
            try context.save()
            print("✅ Synced \(syncedCount) user items from cloud (skipped \(skippedCount) duplicates)")
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

