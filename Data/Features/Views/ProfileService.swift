//
//  ProfileService.swift
//  MovieRanker
//
//  Temporary placeholder implementation to satisfy references from ProfileView.
//  Replace with your app's real profile persistence logic (SwiftData/Cloud/etc.).
//

import Foundation

@MainActor
final class ProfileService {
    static let shared = ProfileService()
    private init() {}

    private let defaults = UserDefaults.standard
    private let kUsername = "profile.username"
    private let kDisplayName = "profile.displayName"

    // Returns the current user's profile if available. Non-throwing convenience wrapper used in ProfileView.
    func getOrCreateMyProfile(defaultDisplayName: String?) async -> UserProfile? {
        let uid = SessionManager.shared.userId ?? "guest"
        var prof = await getMyProfileInternal(userId: uid)
        // Seed display name from default if not set
        if prof.displayName == nil || prof.displayName?.isEmpty == true {
            prof.displayName = defaultDisplayName
            await save(profile: prof)
        }
        return prof
    }

    // Fetch the current user's profile. Replace with your real implementation.
    func getMyProfile() async throws -> UserProfile? {
        let uid = SessionManager.shared.userId ?? "guest"
        return await getMyProfileInternal(userId: uid)
    }

    // MARK: - Persistence helpers (temporary placeholder)
    private func getMyProfileInternal(userId: String) async -> UserProfile {
        let username = defaults.string(forKey: kUsername)
        let displayName = defaults.string(forKey: kDisplayName)
        return UserProfile(id: userId, username: username, displayName: displayName)
    }

    private func save(profile: UserProfile) async {
        defaults.setValue(profile.username, forKey: kUsername)
        defaults.setValue(profile.displayName, forKey: kDisplayName)
    }

    // Update the current user's username. Replace with your real implementation.
    func updateUsername(_ newUsername: String) async throws {
        defaults.setValue(newUsername.isEmpty ? nil : newUsername, forKey: kUsername)
    }

    // Update the current user's display name. Replace with your real implementation.
    func updateDisplayName(_ newDisplayName: String) async throws {
        defaults.setValue(newDisplayName.isEmpty ? nil : newDisplayName, forKey: kDisplayName)
    }

    // MARK: - Username availability (placeholder)
    func isUsernameAvailable(_ username: String) async -> Bool {
        // Placeholder logic: treat any username as available unless it matches a small reserved list.
        let reserved: Set<String> = ["admin", "support", "help", "moderator"]
        if reserved.contains(username.lowercased()) { return false }
        // If it's equal to the currently stored username (case-insensitive), also treat as available for the current user.
        if let current = defaults.string(forKey: kUsername), current.caseInsensitiveCompare(username) == .orderedSame {
            return true
        }
        // No global lookup yet, so return true by default.
        return true
    }

    // Search for users by username or display name. Placeholder implementation.
    func findUsers(query: String) async throws -> [UserProfile] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        // Since this is a local placeholder, return either the current profile if it matches or empty.
        let uid = SessionManager.shared.userId ?? "guest"
        let me = await getMyProfileInternal(userId: uid)
        let nameMatches = (me.username?.lowercased().contains(q) == true) || (me.displayName?.lowercased().contains(q) == true)
        return nameMatches ? [me] : []
    }
}
