// ListService.swift
// Simple cloud sync for custom lists

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
        
        let dto = CustomListDTO(
            id: list.id,
            user_id: user.id,
            name: list.name,
            movie_ids: list.movieIDs.map { $0.uuidString },
            created_at: list.createdAt
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
}

// MARK: - Data Transfer Object

struct CustomListDTO: Codable {
    let id: UUID
    let user_id: UUID
    let name: String
    let movie_ids: [String] // Array of UUID strings
    let created_at: Date
}
