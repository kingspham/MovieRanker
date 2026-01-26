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
    
    func fetchNotifications() async {
        guard let myId = client.auth.currentUser?.id else { return }
        
        do {
            let response: [AppNotification] = try await client
                .from("notifications")
                .select("*, profiles!notifications_actor_id_fkey(*)")
                .eq("user_id", value: myId)
                .order("created_at", ascending: false)
                .limit(30)
                .execute()
                .value
            
            self.notifications = response
            self.unreadCount = response.filter { !$0.read }.count
        } catch {
            print("Fetch error: \(error)")
        }
    }
    
    func markAllRead() async {
        guard let myId = client.auth.currentUser?.id else { return }
        _ = try? await client.from("notifications").update(["read": true]).eq("user_id", value: myId).execute()
        unreadCount = 0
    }
    
    func sendNotification(to userId: UUID, type: String, message: String, relatedId: UUID?) async {
        guard let myId = client.auth.currentUser?.id, userId != myId else { return }
        
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
        } catch {
            print("Notification insert failed: \(error)")
        }
    }
}
