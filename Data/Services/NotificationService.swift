// NotificationService.swift
import Foundation
@preconcurrency import Supabase
import Combine
// import UIKit <--- Removed this to fix the error

@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()
    private var client: SupabaseClient { AuthService.shared.client }

    @Published var notifications: [AppNotification] = []
    @Published var unreadCount: Int = 0 {
        didSet {
            // If you want to set badges later, we can use UserNotifications framework
            // instead of UIKit to keep this file clean.
        }
    }

    // Caching to avoid repeated failed fetches
    private var lastFetchTime: Date?
    private var lastFetchFailed: Bool = false
    private var consecutiveFailures: Int = 0
    private let minFetchInterval: TimeInterval = 60 // Minimum 60 seconds between fetches
    private let failedFetchBackoff: TimeInterval = 300 // 5 minutes after failures

    /// Check if we should fetch notifications (respects caching and backoff)
    func shouldFetch() -> Bool {
        guard let lastFetch = lastFetchTime else { return true }

        let timeSinceLastFetch = Date().timeIntervalSince(lastFetch)

        // If last fetch failed, use longer backoff
        if lastFetchFailed {
            return timeSinceLastFetch >= failedFetchBackoff
        }

        return timeSinceLastFetch >= minFetchInterval
    }

    /// Force fetch (bypasses caching - use sparingly)
    func forceFetch() async {
        await performFetch()
    }

    func fetchNotifications() async {
        // Respect caching to avoid spamming failed requests
        guard shouldFetch() else { return }
        await performFetch()
    }

    private func performFetch() async {
        guard let myId = client.auth.currentUser?.id else {
            print("⚠️ No user ID for notifications")
            return
        }

        lastFetchTime = Date()

        // Try multiple query patterns for robustness
        let queries: [(String, String)] = [
            ("with foreign key join", "*, profiles!notifications_actor_id_fkey(*)"),
            ("with simple join", "*, profiles(*)"),
            ("without join", "id, user_id, actor_id, type, message, related_id, read, created_at")
        ]

        for (name, selectQuery) in queries {
            do {
                let response: [AppNotification] = try await client
                    .from("notifications")
                    .select(selectQuery)
                    .eq("user_id", value: myId)
                    .order("created_at", ascending: false)
                    .limit(30)
                    .execute()
                    .value

                self.notifications = response
                self.unreadCount = response.filter { !$0.read }.count
                self.lastFetchFailed = false
                self.consecutiveFailures = 0
                print("✅ Fetched \(response.count) notifications \(name) (\(self.unreadCount) unread)")
                return // Success, exit loop
            } catch {
                // Only log on first failure to reduce spam
                if consecutiveFailures == 0 {
                    print("⚠️ Notification fetch \(name) failed: \(error.localizedDescription)")
                }
                continue // Try next query pattern
            }
        }

        // All patterns failed
        self.lastFetchFailed = true
        self.consecutiveFailures += 1
        if consecutiveFailures == 1 {
            print("❌ All notification fetch patterns failed - backing off")
        }
    }
    
    func markAllRead() async {
        guard let myId = client.auth.currentUser?.id else { return }
        _ = try? await client.from("notifications").update(["read": true]).eq("user_id", value: myId).execute()
        unreadCount = 0
    }
    
    func sendNotification(to userId: UUID, type: String, message: String, relatedId: UUID?) async {
        guard let myId = client.auth.currentUser?.id, userId != myId else {
            print("⚠️ Skipping self-notification or no user ID")
            return
        }

        struct Payload: Encodable {
            let user_id: UUID
            let actor_id: UUID
            let type: String
            let message: String
            let related_id: UUID?
        }

        let payload = Payload(user_id: userId, actor_id: myId, type: type, message: message, related_id: relatedId)
        do {
            _ = try await AuthService.shared.client.from("notifications").insert(payload).execute()
            print("✅ Sent notification: \(type) to \(userId)")
        } catch {
            // More detailed error logging
            print("❌ Notification insert failed: \(error)")
            print("   Payload: user_id=\(userId), actor_id=\(myId), type=\(type)")
            print("   This may indicate the 'notifications' table doesn't exist or has RLS issues")
        }
    }
}
