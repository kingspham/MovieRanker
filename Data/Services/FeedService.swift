// FeedService.swift
// COMPLETE REPLACEMENT - Copy this entire file

import Foundation
import Supabase
import Combine

@MainActor
class FeedService: ObservableObject {
    static let shared = FeedService()
    private init() {}
    
    @Published var feedItems: [CloudLog] = []
    
    func fetchGlobalFeed() async {
        guard let client = AuthService.shared.client else { return }
        do {
            let response: [CloudLog] = try await client
                .from("logs")
                .select("*, profiles(*), likes(user_id), comments(id)")
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
            self.feedItems = response
        } catch { print("Global Feed Error: \(error)") }
    }
    
    func fetchPersonalizedFeed(myId: String, friendIDs: [String]) async {
        guard let client = AuthService.shared.client else { return }
        if friendIDs.isEmpty { await fetchGlobalFeed(); return }
        var targetIDs = friendIDs; targetIDs.append(myId)
        do {
            let response: [CloudLog] = try await client
                .from("logs")
                .select("*, profiles(*), likes(user_id), comments(id)")
                .in("user_id", values: targetIDs)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
            self.feedItems = response
        } catch { print("Friends Feed Error: \(error)") }
    }
    
    func toggleLike(log: CloudLog) async {
        guard let client = AuthService.shared.client,
              let user = try? await client.auth.session.user else { return }
        
        do {
            let existing: [CloudLog.LikeStub] = try await client
                .from("likes")
                .select("user_id")
                .eq("log_id", value: log.id)
                .eq("user_id", value: user.id)
                .execute()
                .value
            
            if existing.isEmpty {
                struct LikePayload: Encodable { let user_id: UUID; let log_id: UUID }
                let payload = LikePayload(user_id: user.id, log_id: log.id)
                try await client.from("likes").insert(payload).execute()
                
                await NotificationService.shared.sendNotification(
                    to: log.userId,
                    type: "like",
                    message: "liked your review of \(log.title)",
                    relatedId: log.id
                )
            } else {
                _ = try await client
                    .from("likes")
                    .delete()
                    .eq("log_id", value: log.id)
                    .eq("user_id", value: user.id)
                    .execute()
            }
        } catch {
            print("Like Error: \(error)")
        }
    }
    
    func postComment(log: CloudLog, text: String, isSpoiler: Bool) async throws {
        guard let client = AuthService.shared.client, let user = try? await client.auth.session.user else { return }
        let newComment = CommentEncodable(user_id: user.id, log_id: log.id, body: text, is_spoiler: isSpoiler)
        try await client.from("comments").insert(newComment).execute()
        await NotificationService.shared.sendNotification(
            to: log.userId,
            type: "comment",
            message: "commented on your review of \(log.title)",
            relatedId: log.id
        )
    }
    
    // FIXED: Changed movie_title to title and added all fields
    func uploadLog(movie: Movie, score: Int, notes: String?, platform: String?, date: Date) async {
        guard let client = AuthService.shared.client else {
            print("❌ No Supabase client")
            return
        }
        
        guard let user = try? await client.auth.session.user else {
            print("❌ No authenticated user")
            return
        }
        
        let newLog = CloudLogEncodable(
            user_id: user.id,
            title: movie.title,  // Changed from movie_title
            tmdb_id: movie.tmdbID ?? 0,
            year: movie.year ?? 0,
            poster_path: movie.posterPath,
            media_type: movie.mediaType,
            score: score,
            notes: notes,
            platform: platform,
            watched_on: date
        )
        
        do {
            try await client.from("logs").insert(newLog).execute()
            print("✅ Uploaded log to cloud: \(movie.title) - Score: \(score)")
        } catch {
            print("❌ Upload Error: \(error)")
        }
    }
    
    func fetchUserLogs(userId: String) async -> [PublicLog] {
        guard let client = AuthService.shared.client else { return [] }
        struct PublicLogDTO: Codable {
            let id: UUID
            let title: String?  // Changed from movie_title
            let poster_path: String?
            let score: Int?
            let tmdb_id: Int?
        }
        do {
            let response: [PublicLogDTO] = try await client
                .from("logs")
                .select("id, title, poster_path, score, tmdb_id")  // Changed from movie_title
                .eq("user_id", value: userId)
                .order("watched_on", ascending: false)
                .limit(20)
                .execute()
                .value
            return response.map { PublicLog(id: $0.id, title: $0.title ?? "Unknown", posterPath: $0.poster_path, score: $0.score, tmdbID: $0.tmdb_id ?? 0) }
        } catch {
            print("Error fetching user logs: \(error)")
            return []
        }
    }
}

// FIXED: Changed movie_title to title and added all fields
struct CloudLogEncodable: Codable {
    let user_id: UUID
    let title: String  // Changed from movie_title
    let tmdb_id: Int
    let year: Int
    let poster_path: String?
    let media_type: String
    let score: Int
    let notes: String?
    let platform: String?
    let watched_on: Date
}

struct CommentEncodable: Codable {
    let user_id: UUID
    let log_id: UUID
    let body: String
    let is_spoiler: Bool
}
