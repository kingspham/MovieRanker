// ListService.swift
// Cloud sync for custom lists

import Foundation
import Supabase
import SwiftData

@MainActor
class ListService {
    static let shared = ListService()
    private init() {}

    /// Upload a single custom list to cloud
    func uploadList(_ list: CustomList) async {
        guard let client = AuthService.shared.client else {
            print("❌ No Supabase client")
            return
        }

        guard let user = try? await client.auth.session.user else {
            print("❌ No authenticated user")
            return
        }

        let dto = CustomListUploadDTO(
            id: list.id,
            user_id: user.id,
            name: list.name,
            details: list.details,
            movie_ids: list.movieIDs.map { $0.uuidString },
            created_at: ISO8601DateFormatter().string(from: list.createdAt),
            is_public: list.isPublic
        )

        do {
            try await client.from("custom_lists")
                .upsert(dto)
                .execute()
            print("✅ Uploaded list: \(list.name) with \(list.movieIDs.count) items")
        } catch {
            print("❌ Upload Error: \(error)")
        }
    }

    /// Download and sync all lists from cloud
    func syncLists(context: ModelContext) async {
        guard let client = AuthService.shared.client else {
            print("❌ No Supabase client for list sync")
            return
        }

        guard let user = try? await client.auth.session.user else {
            print("❌ No authenticated user for list sync")
            return
        }

        do {
            let cloudLists: [CustomListDownloadDTO] = try await client
                .from("custom_lists")
                .select()
                .eq("user_id", value: user.id)
                .execute()
                .value

            print("📥 Downloaded \(cloudLists.count) lists from cloud")

            // Get all local lists
            let localLists = (try? context.fetch(FetchDescriptor<CustomList>())) ?? []
            let localListIDs = Set(localLists.map { $0.id })

            for cloudList in cloudLists {
                // Check if list already exists locally
                if localListIDs.contains(cloudList.id) {
                    // Update existing list
                    if let existingList = localLists.first(where: { $0.id == cloudList.id }) {
                        existingList.name = cloudList.name
                        existingList.details = cloudList.details ?? ""
                        existingList.isPublic = cloudList.is_public
                        existingList.movieIDs = cloudList.movie_ids.compactMap { UUID(uuidString: $0) }
                    }
                } else {
                    // Create new list
                    let newList = CustomList(
                        name: cloudList.name,
                        details: cloudList.details ?? "",
                        ownerId: user.id.uuidString,
                        isPublic: cloudList.is_public
                    )
                    // Set the ID to match the cloud
                    newList.id = cloudList.id
                    newList.movieIDs = cloudList.movie_ids.compactMap { UUID(uuidString: $0) }
                    if let createdAt = ISO8601DateFormatter().date(from: cloudList.created_at) {
                        newList.createdAt = createdAt
                    }
                    context.insert(newList)
                }
            }

            try? context.save()
            print("✅ List sync complete")
        } catch {
            print("❌ List sync error: \(error)")
        }
    }
}

// MARK: - Data Transfer Objects

struct CustomListUploadDTO: Codable {
    let id: UUID
    let user_id: UUID
    let name: String
    let details: String
    let movie_ids: [String]
    let created_at: String
    let is_public: Bool
}

struct CustomListDownloadDTO: Codable {
    let id: UUID
    let user_id: UUID
    let name: String
    let details: String?
    let movie_ids: [String]
    let created_at: String
    let is_public: Bool
}
