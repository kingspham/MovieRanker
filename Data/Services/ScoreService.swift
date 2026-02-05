// ScoreService.swift
// REPLACE your current ScoreService.swift with this version

import Foundation
import Supabase
import SwiftData
import Combine

@MainActor
class ScoreService: ObservableObject {
    static let shared = ScoreService()
    private init() {}
    
    // Upload a single score after ranking
    func uploadScore(_ score: Score, movie: Movie) async {
        guard let client = AuthService.shared.client,
              let user = try? await client.auth.session.user else {
            print("❌ No auth client or user")
            return
        }
        
        let scoreDTO = ScoreDTO(
            user_id: user.id,
            movie_id: score.movieID,
            tmdb_id: movie.tmdbID,
            display_100: score.display100,
            latent: score.latent,
            variance: score.variance
        )
        
        do {
            // Upsert (insert or update if exists)
            try await client.from("scores")
                .upsert(scoreDTO)
                .execute()
            print("✅ Uploaded score for \(movie.title): \(score.display100)")
        } catch {
            print("❌ Error uploading score: \(error)")
        }
    }
    
    // Upload all scores after re-ranking (when you do comparisons)
    func uploadAllScores(scores: [Score], context: ModelContext) async {
        guard let client = AuthService.shared.client,
              let user = try? await client.auth.session.user else {
            print("❌ No auth client or user for batch upload")
            return
        }
        
        var scoreDTOs: [ScoreDTO] = []
        
        // Fetch all movies once for efficiency
        let allMovies = (try? context.fetch(FetchDescriptor<Movie>())) ?? []

        for score in scores {
            // Find the movie for this score
            let targetID = score.movieID

            if let movie = allMovies.first(where: { $0.id == targetID }) {
                scoreDTOs.append(ScoreDTO(
                    user_id: user.id,
                    movie_id: score.movieID,
                    tmdb_id: movie.tmdbID,
                    display_100: score.display100,
                    latent: score.latent,
                    variance: score.variance
                ))
            }
        }
        
        guard !scoreDTOs.isEmpty else { return }
        
        do {
            // Batch upsert all scores
            try await client.from("scores")
                .upsert(scoreDTOs)
                .execute()
            print("✅ Batch uploaded \(scoreDTOs.count) scores")
        } catch {
            print("❌ Error batch uploading scores: \(error)")
        }
    }
    
    // Delete a score when a rating is removed
    func deleteScore(movieID: UUID) async {
        guard let client = AuthService.shared.client,
              let user = try? await client.auth.session.user else {
            print("❌ No auth for deleting score")
            return
        }
        
        do {
            _ = try await client
                .from("scores")
                .delete()
                .eq("user_id", value: user.id)
                .eq("movie_id", value: movieID)
                .execute()
            print("✅ Deleted score for movie \(movieID)")
        } catch {
            print("❌ Error deleting score: \(error)")
        }
    }
    
    /// Fetch scores for a specific user (for Watch With friend predictions)
    func fetchScoresForUser(userId: UUID) async -> [ScoreDTO] {
        guard let client = AuthService.shared.client else {
            print("❌ No auth client for fetching friend scores")
            return []
        }

        do {
            let response: [ScoreDTO] = try await client
                .from("scores")
                .select()
                .eq("user_id", value: userId)
                .order("display_100", ascending: false)
                .execute()
                .value
            print("✅ Fetched \(response.count) scores for user \(userId)")
            return response
        } catch {
            print("❌ Error fetching user scores: \(error)")
            return []
        }
    }

    // Fetch all user's scores from cloud (for initial sync or pulling to new device)
    func fetchAllScores() async -> [ScoreDTO] {
        guard let client = AuthService.shared.client,
              let user = try? await client.auth.session.user else {
            print("❌ No auth for fetching scores")
            return []
        }
        
        do {
            let response: [ScoreDTO] = try await client
                .from("scores")
                .select()
                .eq("user_id", value: user.id)
                .order("display_100", ascending: false)
                .execute()
                .value
            print("✅ Fetched \(response.count) scores from cloud")
            return response
        } catch {
            print("❌ Error fetching scores: \(error)")
            return []
        }
    }
    
    // Sync: Download scores from cloud and merge with local database
    func syncScores(context: ModelContext) async {
        let cloudScores = await fetchAllScores()
        
        guard !cloudScores.isEmpty else {
            print("ℹ️ No cloud scores to sync")
            return
        }
        
        var syncedCount = 0

        // Fetch all local scores once
        let allLocalScores = (try? context.fetch(FetchDescriptor<Score>())) ?? []

        for cloudScore in cloudScores {
            // Check if score exists locally
            if let localScore = allLocalScores.first(where: { $0.movieID == cloudScore.movie_id }) {
                // Update local with cloud data if different
                if localScore.display100 != cloudScore.display_100 {
                    localScore.display100 = cloudScore.display_100
                    localScore.latent = cloudScore.latent
                    localScore.variance = cloudScore.variance
                    syncedCount += 1
                }
            } else {
                // Create new local score from cloud
                let newScore = Score(
                    movieID: cloudScore.movie_id,
                    display100: cloudScore.display_100,
                    latent: cloudScore.latent,
                    variance: cloudScore.variance,
                    ownerId: cloudScore.user_id.uuidString
                )
                context.insert(newScore)
                syncedCount += 1
            }
        }
        
        do {
            try context.save()
            print("✅ Synced \(syncedCount) scores from cloud")
        } catch {
            print("❌ Error saving synced scores: \(error)")
        }
    }
}

// Data Transfer Object for Supabase
struct ScoreDTO: Codable {
    let user_id: UUID
    let movie_id: UUID
    let tmdb_id: Int?
    let display_100: Int
    let latent: Double
    let variance: Double
}
