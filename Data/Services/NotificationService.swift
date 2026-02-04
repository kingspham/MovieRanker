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
    private var isFetching: Bool = false
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
        guard !isFetching else { return } // Prevent concurrent fetches
        guard let myId = client.auth.currentUser?.id else {
            print("⚠️ No user ID for notifications")
            return
        }

        isFetching = true
        defer { isFetching = false }
        lastFetchTime = Date()
        print("🔔 Fetching notifications for user: \(myId)")

        // Try user_id column first, then recipient_id as fallback
        let columnOptions = ["user_id", "recipient_id"]

        for userColumn in columnOptions {
            do {
                var response: [AppNotification] = try await client
                    .from("notifications")
                    .select("id, user_id, actor_id, type, message, related_id, read, created_at")
                    .eq(userColumn, value: myId)
                    .order("created_at", ascending: false)
                    .limit(30)
                    .execute()
                    .value

                // Fetch actor profiles separately (FK join doesn't exist in schema)
                if !response.isEmpty {
                    await enrichNotificationsWithProfiles(&response)
                }

                self.notifications = response
                self.unreadCount = response.filter { !$0.read }.count
                self.lastFetchFailed = false
                self.consecutiveFailures = 0
                print("✅ Fetched \(response.count) notifications via \(userColumn) (\(self.unreadCount) unread)")
                return // Success, stop trying
            } catch {
                if consecutiveFailures == 0 {
                    print("⚠️ Notification fetch via \(userColumn) failed: \(error.localizedDescription)")
                }
                continue // Try next column
            }
        }

        // All patterns failed
        self.lastFetchFailed = true
        self.consecutiveFailures += 1
        print("❌ All notification fetch patterns failed (attempt \(consecutiveFailures)) - backing off")
    }

    /// Fetch profiles for notifications that don't have actor data
    private func enrichNotificationsWithProfiles(_ notifications: inout [AppNotification]) async {
        let actorIds = Set(notifications.filter { $0.actor == nil }.map { $0.actorId })
        guard !actorIds.isEmpty else { return }

        do {
            let profiles: [SocialProfile] = try await client
                .from("profiles")
                .select("*")
                .in("id", values: Array(actorIds))
                .execute()
                .value

            let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

            // Create new notifications with enriched actor data
            notifications = notifications.map { notif in
                if notif.actor == nil, let profile = profileMap[notif.actorId] {
                    return notif.withActor(profile)
                }
                return notif
            }
            print("✅ Enriched notifications with \(profiles.count) profiles")
        } catch {
            print("⚠️ Failed to fetch actor profiles: \(error)")
        }
    }
    
    func markAllRead() async {
        guard let myId = client.auth.currentUser?.id else { return }
        _ = try? await client.from("notifications").update(["read": true]).eq("user_id", value: myId).execute()
        _ = try? await client.from("notifications").update(["read": true]).eq("recipient_id", value: myId).execute()
        unreadCount = 0
    }
    
    func sendNotification(to userId: UUID, type: String, message: String, relatedId: UUID?) async {
        guard let myId = client.auth.currentUser?.id else {
            print("⚠️ Cannot send notification: no current user")
            return
        }

        // Don't send notifications to yourself
        if userId == myId {
            print("⚠️ Skipping self-notification")
            return
        }

        struct Payload: Encodable {
            let user_id: UUID
            let actor_id: UUID
            let type: String
            let message: String
            let related_id: UUID?
            let read: Bool
        }

        let payload = Payload(
            user_id: userId,
            actor_id: myId,
            type: type,
            message: message,
            related_id: relatedId,
            read: false
        )

        print("📤 Sending notification: type=\(type), to=\(userId), from=\(myId)")

        do {
            _ = try await AuthService.shared.client.from("notifications").insert(payload).execute()
            print("✅ Notification sent successfully: \(type) to \(userId)")
        } catch {
            // More detailed error logging
            print("❌ Notification insert failed: \(error)")
            print("   Payload: user_id=\(userId), actor_id=\(myId), type=\(type), message=\(message)")
            print("   This may indicate:")
            print("     - The 'notifications' table doesn't exist in Supabase")
            print("     - RLS (Row Level Security) policies are blocking the insert")
            print("     - The table schema doesn't match the Payload structure")
        }
    }
}
