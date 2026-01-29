// PredictionEngine.swift
// IMPROVED VERSION - Better predictions with more variation and accuracy

import Foundation
import SwiftData

struct PredictionExplanation: Sendable {
    let score: Double      // 0..10 scale
    let confidence: Double // 0..1
    let reasons: [String]
    let debugInfo: String? // For troubleshooting
}

protocol PredictionEngine {
    func predict(for movie: Movie, in context: ModelContext, userId: String) -> PredictionExplanation
}

final class LinearPredictionEngine: PredictionEngine {

    // Cached data for batch predictions (avoids repeated fetches)
    private var cachedScores: [Score]?
    private var cachedLogs: [LogEntry]?
    private var cachedMovies: [UUID: Movie]?
    private var cachedUserId: String?

    /// Batch prediction - fetches data once and predicts for all movies efficiently
    func predictBatch(for movies: [Movie], in context: ModelContext, userId: String) -> [UUID: PredictionExplanation] {
        // Fetch all data once
        let allScoresDescriptor = FetchDescriptor<Score>()
        let allScores = (try? context.fetch(allScoresDescriptor)) ?? []
        let userScores = allScores.filter { $0.ownerId == userId || $0.ownerId == "guest" }

        let allLogsDescriptor = FetchDescriptor<LogEntry>()
        let allLogs = (try? context.fetch(allLogsDescriptor)) ?? []
        let userLogs = allLogs.filter { $0.ownerId == userId || $0.ownerId == "guest" }

        let allMoviesDescriptor = FetchDescriptor<Movie>()
        let allMovies = (try? context.fetch(allMoviesDescriptor)) ?? []
        let movieLookup = Dictionary(uniqueKeysWithValues: allMovies.map { ($0.id, $0) })

        // Build attribute map once
        let attributeScores = buildAttributeMap(userScores: userScores, userLogs: userLogs, movieLookup: movieLookup)

        // Calculate predictions for all movies
        var results: [UUID: PredictionExplanation] = [:]
        for movie in movies {
            let prediction = predictWithCachedData(
                for: movie,
                userScores: userScores,
                userLogs: userLogs,
                movieLookup: movieLookup,
                attributeScores: attributeScores,
                userId: userId
            )
            results[movie.id] = prediction
        }

        return results
    }

    func predict(for movie: Movie, in context: ModelContext, userId: String) -> PredictionExplanation {
        // Fetch all scores and filter in memory
        let allScoresDescriptor = FetchDescriptor<Score>()
        let allScores = (try? context.fetch(allScoresDescriptor)) ?? []
        let userScores = allScores.filter { $0.ownerId == userId || $0.ownerId == "guest" }

        // Fetch all logs and filter in memory
        let allLogsDescriptor = FetchDescriptor<LogEntry>()
        let allLogs = (try? context.fetch(allLogsDescriptor)) ?? []
        let userLogs = allLogs.filter { $0.ownerId == userId || $0.ownerId == "guest" }

        let hasScores = !userScores.isEmpty
        let hasLogs = !userLogs.isEmpty

        if !hasScores && !hasLogs {
            // No data - use critic scores if available
            let criticScore = getCriticBasedPrediction(for: movie)
            return PredictionExplanation(
                score: criticScore,
                confidence: 0.2,
                reasons: ["Based on critic consensus"],
                debugInfo: "No user data - using critic scores"
            )
        }

        // Build attribute map from user's ratings
        var attributeScores: [String: [Double]] = [:]  // Simplified: just store scores

        // Process explicit scores
        let sameTypeScores = userScores.filter { score in
            guard let m = fetchMovie(id: score.movieID, context: context) else { return false }
            return m.mediaType == movie.mediaType
        }

        for score in sameTypeScores {
            guard let rankedMovie = fetchMovie(id: score.movieID, context: context) else { continue }
            let rating = Double(score.display100) / 10.0
            addMovieAttributes(movie: rankedMovie, rating: rating, to: &attributeScores)
        }

        // Also track what the user has watched but not rated (implicit positive signal)
        let scoredMovieIDs = Set(sameTypeScores.compactMap { fetchMovie(id: $0.movieID, context: context)?.id })

        for log in userLogs {
            guard let watchedMovie = log.movie,
                  watchedMovie.mediaType == movie.mediaType,
                  !scoredMovieIDs.contains(watchedMovie.id) else { continue }
            // Implicit: watching = mild interest (6.5/10)
            addMovieAttributes(movie: watchedMovie, rating: 6.5, to: &attributeScores)
        }

        if sameTypeScores.isEmpty {
            let criticScore = getCriticBasedPrediction(for: movie)
            return PredictionExplanation(
                score: criticScore,
                confidence: 0.25,
                reasons: ["Rate some \(movie.mediaType)s first", "Using critic scores"],
                debugInfo: "No \(movie.mediaType) ratings yet"
            )
        }

        // Calculate prediction using MULTIPLE methods and combine them
        var predictions: [(score: Double, weight: Double, reason: String)] = []

        // METHOD 1: Genre-based prediction (strongest signal)
        let genrePrediction = predictByGenres(movie: movie, attributeScores: attributeScores)
        if let gp = genrePrediction {
            predictions.append((gp.score, gp.confidence * 3.0, gp.reason))
        }

        // METHOD 2: Talent-based prediction (directors, actors)
        let talentPrediction = predictByTalent(movie: movie, attributeScores: attributeScores)
        if let tp = talentPrediction {
            predictions.append((tp.score, tp.confidence * 2.5, tp.reason))
        }

        // METHOD 3: Era/decade preference
        let eraPrediction = predictByEra(movie: movie, attributeScores: attributeScores)
        if let ep = eraPrediction {
            predictions.append((ep.score, ep.confidence * 1.0, ep.reason))
        }

        // METHOD 4: Critic score adjustment (use as anchor)
        let criticScore = getCriticBasedPrediction(for: movie)
        let userAvgScore = sameTypeScores.map { Double($0.display100) / 10.0 }.reduce(0, +) / Double(sameTypeScores.count)
        let userBias = userAvgScore - 6.5  // How much does user deviate from "average"?
        let adjustedCriticScore = criticScore + (userBias * 0.5)
        predictions.append((adjustedCriticScore, 0.5, "Critic consensus"))

        // Combine all predictions
        var finalScore: Double
        var topReasons: [String] = []
        var debugInfo = "Data: \(sameTypeScores.count) rated"

        if predictions.isEmpty {
            finalScore = 5.0
            topReasons = ["Not enough data"]
        } else {
            // Sort by weight
            let sortedPredictions = predictions.sorted { $0.weight > $1.weight }

            // Weight-averaged combination
            let totalWeight = predictions.reduce(0) { $0 + $1.weight }
            let weightedSum = predictions.reduce(0) { $0 + ($1.score * $1.weight) }
            finalScore = weightedSum / totalWeight

            // But also allow STRONG signals to pull the score more extremely
            // If a genre/talent match is very positive or negative, amplify it
            if let strongest = sortedPredictions.first, strongest.weight > 2.0 {
                let deviation = strongest.score - finalScore
                // Amplify strong signals
                if abs(deviation) > 1.0 {
                    finalScore += deviation * 0.3
                }
            }

            topReasons = sortedPredictions.prefix(3).map { $0.reason }
            debugInfo += " | Predictions: \(sortedPredictions.map { "\($0.reason): \(String(format: "%.1f", $0.score))" }.joined(separator: ", "))"
        }

        // Calculate confidence
        let confidence = min(Double(sameTypeScores.count) / 10.0, 0.9)

        // Allow more extreme scores - only clamp to 1-10 range
        finalScore = min(max(finalScore, 1.0), 10.0)

        return PredictionExplanation(
            score: finalScore,
            confidence: confidence,
            reasons: topReasons,
            debugInfo: debugInfo
        )
    }

    // MARK: - Batch Prediction Helpers

    /// Build attribute map from user's ratings (for batch predictions)
    private func buildAttributeMap(userScores: [Score], userLogs: [LogEntry], movieLookup: [UUID: Movie]) -> [String: [Double]] {
        var attributeScores: [String: [Double]] = [:]

        // Process explicit scores
        for score in userScores {
            guard let rankedMovie = movieLookup[score.movieID] else { continue }
            let rating = Double(score.display100) / 10.0
            addMovieAttributes(movie: rankedMovie, rating: rating, to: &attributeScores)
        }

        // Process watched but not rated (implicit positive signal)
        let scoredMovieIDs = Set(userScores.map { $0.movieID })
        for log in userLogs {
            guard let watchedMovie = log.movie,
                  !scoredMovieIDs.contains(watchedMovie.id) else { continue }
            addMovieAttributes(movie: watchedMovie, rating: 6.5, to: &attributeScores)
        }

        return attributeScores
    }

    /// Predict using pre-fetched cached data (for batch predictions)
    private func predictWithCachedData(
        for movie: Movie,
        userScores: [Score],
        userLogs: [LogEntry],
        movieLookup: [UUID: Movie],
        attributeScores: [String: [Double]],
        userId: String
    ) -> PredictionExplanation {
        let hasScores = !userScores.isEmpty
        let hasLogs = !userLogs.isEmpty

        if !hasScores && !hasLogs {
            let criticScore = getCriticBasedPrediction(for: movie)
            return PredictionExplanation(
                score: criticScore,
                confidence: 0.2,
                reasons: ["Based on critic consensus"],
                debugInfo: "No user data - using critic scores"
            )
        }

        // Filter scores for same media type using lookup
        let sameTypeScores = userScores.filter { score in
            guard let m = movieLookup[score.movieID] else { return false }
            return m.mediaType == movie.mediaType
        }

        if sameTypeScores.isEmpty {
            let criticScore = getCriticBasedPrediction(for: movie)
            return PredictionExplanation(
                score: criticScore,
                confidence: 0.25,
                reasons: ["Rate some \(movie.mediaType)s first", "Using critic scores"],
                debugInfo: "No \(movie.mediaType) ratings yet"
            )
        }

        // Calculate prediction using multiple methods
        var predictions: [(score: Double, weight: Double, reason: String)] = []

        if let gp = predictByGenres(movie: movie, attributeScores: attributeScores) {
            predictions.append((gp.score, gp.confidence * 3.0, gp.reason))
        }
        if let tp = predictByTalent(movie: movie, attributeScores: attributeScores) {
            predictions.append((tp.score, tp.confidence * 2.5, tp.reason))
        }
        if let ep = predictByEra(movie: movie, attributeScores: attributeScores) {
            predictions.append((ep.score, ep.confidence * 1.0, ep.reason))
        }

        let criticScore = getCriticBasedPrediction(for: movie)
        let userAvgScore = sameTypeScores.map { Double($0.display100) / 10.0 }.reduce(0, +) / Double(sameTypeScores.count)
        let userBias = userAvgScore - 6.5
        let adjustedCriticScore = criticScore + (userBias * 0.5)
        predictions.append((adjustedCriticScore, 0.5, "Critic consensus"))

        var finalScore: Double
        var topReasons: [String] = []

        if predictions.isEmpty {
            finalScore = 5.0
            topReasons = ["Not enough data"]
        } else {
            let sortedPredictions = predictions.sorted { $0.weight > $1.weight }
            let totalWeight = predictions.reduce(0) { $0 + $1.weight }
            let weightedSum = predictions.reduce(0) { $0 + ($1.score * $1.weight) }
            finalScore = weightedSum / totalWeight

            if let strongest = sortedPredictions.first, strongest.weight > 2.0 {
                let deviation = strongest.score - finalScore
                if abs(deviation) > 1.0 {
                    finalScore += deviation * 0.3
                }
            }

            topReasons = sortedPredictions.prefix(3).map { $0.reason }
        }

        let confidence = min(Double(sameTypeScores.count) / 10.0, 0.9)
        finalScore = min(max(finalScore, 1.0), 10.0)

        return PredictionExplanation(
            score: finalScore,
            confidence: confidence,
            reasons: topReasons,
            debugInfo: nil
        )
    }

    // MARK: - Prediction Methods

    private func predictByGenres(movie: Movie, attributeScores: [String: [Double]]) -> (score: Double, confidence: Double, reason: String)? {
        var genreScores: [Double] = []
        var matchedGenres: [String] = []

        for genreID in movie.genreIDs {
            let key = "genre:\(genreID)"
            if let scores = attributeScores[key], !scores.isEmpty {
                let avg = scores.reduce(0, +) / Double(scores.count)
                genreScores.append(avg)
                matchedGenres.append(genreIDToString(genreID))
            }
        }

        // Also check genre combos
        if movie.genreIDs.count >= 2 {
            let sorted = movie.genreIDs.sorted()
            for i in 0..<sorted.count {
                for j in (i+1)..<sorted.count {
                    let key = "combo:\(sorted[i])-\(sorted[j])"
                    if let scores = attributeScores[key], !scores.isEmpty {
                        let avg = scores.reduce(0, +) / Double(scores.count)
                        // Combo matches are strong signals - weight them more
                        genreScores.append(avg)
                        genreScores.append(avg)  // Double weight for combos
                    }
                }
            }
        }

        guard !genreScores.isEmpty else { return nil }

        let avgScore = genreScores.reduce(0, +) / Double(genreScores.count)
        let confidence = min(Double(genreScores.count) / 5.0, 1.0)
        let reason = matchedGenres.isEmpty ? "Genre match" : matchedGenres.prefix(2).joined(separator: ", ")

        return (avgScore, confidence, reason)
    }

    private func predictByTalent(movie: Movie, attributeScores: [String: [Double]]) -> (score: Double, confidence: Double, reason: String)? {
        var talentScores: [(score: Double, name: String, isDirector: Bool)] = []

        for tag in movie.tags {
            if tag.starts(with: "dir:") {
                if let scores = attributeScores[tag], !scores.isEmpty {
                    let avg = scores.reduce(0, +) / Double(scores.count)
                    let name = tag.replacingOccurrences(of: "dir:", with: "").replacingOccurrences(of: "_", with: " ").capitalized
                    talentScores.append((avg, name, true))
                }
            } else if tag.starts(with: "actor:") {
                if let scores = attributeScores[tag], !scores.isEmpty {
                    let avg = scores.reduce(0, +) / Double(scores.count)
                    let name = tag.replacingOccurrences(of: "actor:", with: "").replacingOccurrences(of: "_", with: " ").capitalized
                    talentScores.append((avg, name, false))
                }
            }
        }

        guard !talentScores.isEmpty else { return nil }

        // Directors weighted more than actors
        var weightedSum = 0.0
        var totalWeight = 0.0
        var bestMatch = ""

        for talent in talentScores {
            let weight = talent.isDirector ? 2.0 : 1.0
            weightedSum += talent.score * weight
            totalWeight += weight
            if bestMatch.isEmpty {
                bestMatch = talent.isDirector ? "Director: \(talent.name)" : "Stars \(talent.name)"
            }
        }

        let avgScore = weightedSum / totalWeight
        let confidence = min(Double(talentScores.count) / 3.0, 1.0)

        return (avgScore, confidence, bestMatch)
    }

    private func predictByEra(movie: Movie, attributeScores: [String: [Double]]) -> (score: Double, confidence: Double, reason: String)? {
        guard let year = movie.year else { return nil }

        var scores: [Double] = []

        // Check decade
        let decade = (year / 10) * 10
        if let decadeScores = attributeScores["decade:\(decade)"], !decadeScores.isEmpty {
            scores.append(contentsOf: decadeScores)
        }

        // Check age category
        let age = 2026 - year
        let ageKey: String
        if age < 2 { ageKey = "age:new" }
        else if age < 5 { ageKey = "age:recent" }
        else if age < 15 { ageKey = "age:modern" }
        else if age < 30 { ageKey = "age:classic" }
        else { ageKey = "age:vintage" }

        if let ageScores = attributeScores[ageKey], !ageScores.isEmpty {
            scores.append(contentsOf: ageScores)
        }

        guard !scores.isEmpty else { return nil }

        let avgScore = scores.reduce(0, +) / Double(scores.count)
        let confidence = min(Double(scores.count) / 5.0, 0.8)

        return (avgScore, confidence, "\(decade)s")
    }

    private func getCriticBasedPrediction(for movie: Movie) -> Double {
        // Use available critic scores to estimate a baseline
        var scores: [Double] = []

        // IMDb (0-10 scale)
        if let imdbStr = movie.imdbRating, let imdb = Double(imdbStr), imdb > 0 {
            scores.append(imdb)
        }

        // Metacritic (0-100 scale -> 0-10)
        if let metaStr = movie.metaScore, let meta = Double(metaStr), meta > 0 {
            scores.append(meta / 10.0)
        }

        // Rotten Tomatoes (0-100% -> 0-10)
        if let rtStr = movie.rottenTomatoesRating {
            let cleaned = rtStr.replacingOccurrences(of: "%", with: "")
            if let rt = Double(cleaned), rt > 0 {
                scores.append(rt / 10.0)
            }
        }

        if scores.isEmpty {
            return 6.0  // Default neutral-ish
        }

        return scores.reduce(0, +) / Double(scores.count)
    }

    private func fetchMovie(id: UUID, context: ModelContext) -> Movie? {
        let desc = FetchDescriptor<Movie>()
        let allMovies = (try? context.fetch(desc)) ?? []
        return allMovies.first { $0.id == id }
    }

    /// Add movie attributes to the map
    private func addMovieAttributes(
        movie: Movie,
        rating: Double,
        to attributeScores: inout [String: [Double]]
    ) {
        // Genres
        for genreID in movie.genreIDs {
            attributeScores["genre:\(genreID)", default: []].append(rating)
        }

        // Genre combos
        if movie.genreIDs.count >= 2 {
            let sorted = movie.genreIDs.sorted()
            for i in 0..<sorted.count {
                for j in (i+1)..<sorted.count {
                    attributeScores["combo:\(sorted[i])-\(sorted[j])", default: []].append(rating)
                }
            }
        }

        // Talent
        for tag in movie.tags {
            if tag.starts(with: "dir:") || tag.starts(with: "actor:") {
                attributeScores[tag, default: []].append(rating)
            }
        }

        // Era
        if let year = movie.year {
            let decade = (year / 10) * 10
            attributeScores["decade:\(decade)", default: []].append(rating)

            let age = 2026 - year
            if age < 2 { attributeScores["age:new", default: []].append(rating) }
            else if age < 5 { attributeScores["age:recent", default: []].append(rating) }
            else if age < 15 { attributeScores["age:modern", default: []].append(rating) }
            else if age < 30 { attributeScores["age:classic", default: []].append(rating) }
            else { attributeScores["age:vintage", default: []].append(rating) }
        }
    }

    private func genreIDToString(_ id: Int) -> String {
        switch id {
        case 28: return "Action"
        case 12: return "Adventure"
        case 16: return "Animation"
        case 35: return "Comedy"
        case 80: return "Crime"
        case 99: return "Documentary"
        case 18: return "Drama"
        case 10751: return "Family"
        case 14: return "Fantasy"
        case 36: return "History"
        case 27: return "Horror"
        case 10402: return "Music"
        case 9648: return "Mystery"
        case 10749: return "Romance"
        case 878: return "Sci-Fi"
        case 10770: return "TV Movie"
        case 53: return "Thriller"
        case 10752: return "War"
        case 37: return "Western"
        default: return "Genre"
        }
    }
}
