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
            // No data - use critic scores if available with variety
            let criticScore = getCriticBasedPrediction(for: movie)
            return PredictionExplanation(
                score: criticScore,
                confidence: 0.2,
                reasons: ["Based on critic consensus"],
                debugInfo: "No user data - using critic scores"
            )
        }

        // Build attribute map from user's ratings
        var attributeScores: [String: [Double]] = [:]

        // Process explicit scores - include all media types for broader learning
        let sameTypeScores = userScores.filter { score in
            guard let m = fetchMovie(id: score.movieID, context: context) else { return false }
            return m.mediaType == movie.mediaType
        }

        // Also get cross-type scores for genre learning
        let allUserScoresWithMovies = userScores.compactMap { score -> (Score, Movie)? in
            guard let m = fetchMovie(id: score.movieID, context: context) else { return nil }
            return (score, m)
        }

        for (score, rankedMovie) in allUserScoresWithMovies {
            let rating = Double(score.display100) / 10.0
            // Weight same-type ratings higher
            let weight = rankedMovie.mediaType == movie.mediaType ? 1.0 : 0.5
            addMovieAttributesWeighted(movie: rankedMovie, rating: rating, weight: weight, to: &attributeScores)
        }

        // Track watched but not rated (implicit positive signal)
        let scoredMovieIDs = Set(userScores.map { $0.movieID })

        for log in userLogs {
            guard let watchedMovie = log.movie,
                  !scoredMovieIDs.contains(watchedMovie.id) else { continue }
            // Implicit: watching = mild interest (6.5/10)
            let weight = watchedMovie.mediaType == movie.mediaType ? 0.7 : 0.3
            addMovieAttributesWeighted(movie: watchedMovie, rating: 6.5, weight: weight, to: &attributeScores)
        }

        if sameTypeScores.isEmpty && userScores.isEmpty {
            let criticScore = getCriticBasedPrediction(for: movie)
            return PredictionExplanation(
                score: criticScore,
                confidence: 0.25,
                reasons: ["Rate some \(movie.mediaType)s first", "Using critic scores"],
                debugInfo: "No \(movie.mediaType) ratings yet"
            )
        }

        // Calculate prediction using MULTIPLE methods with stronger differentiation
        var predictions: [(score: Double, weight: Double, reason: String)] = []

        // METHOD 1: Genre-based prediction (STRONGEST signal - doubled weight)
        let genrePrediction = predictByGenres(movie: movie, attributeScores: attributeScores)
        if let gp = genrePrediction {
            predictions.append((gp.score, gp.confidence * 5.0, gp.reason))
        }

        // METHOD 2: Talent-based prediction (directors, actors)
        let talentPrediction = predictByTalent(movie: movie, attributeScores: attributeScores)
        if let tp = talentPrediction {
            predictions.append((tp.score, tp.confidence * 4.0, tp.reason))
        }

        // METHOD 3: Era/decade preference
        let eraPrediction = predictByEra(movie: movie, attributeScores: attributeScores)
        if let ep = eraPrediction {
            predictions.append((ep.score, ep.confidence * 1.5, ep.reason))
        }

        // METHOD 4: User's average rating bias (personalized baseline)
        let relevantScores = sameTypeScores.isEmpty ? userScores : sameTypeScores
        if !relevantScores.isEmpty {
            let scores = relevantScores.map { Double($0.display100) / 10.0 }
            let userAvg = scores.reduce(0, +) / Double(scores.count)
            let userStdDev = sqrt(scores.map { pow($0 - userAvg, 2) }.reduce(0, +) / Double(scores.count))

            // User baseline is their average with some variance consideration
            let baselineScore = userAvg + (userStdDev > 1.0 ? 0.0 : 0.5) // Harsh raters get slight boost
            predictions.append((baselineScore, 1.0, "Your rating style"))
        }

        // METHOD 5: Critic score (lower weight - user prefs matter more)
        let criticScore = getCriticBasedPrediction(for: movie)
        if criticScore != 6.0 { // Only add if we have real critic data
            predictions.append((criticScore, 0.8, "Critic consensus"))
        }

        // Combine predictions with emphasis on STRONGEST signals
        var finalScore: Double
        var topReasons: [String] = []
        var debugInfo = "Data: \(relevantScores.count) rated"

        if predictions.isEmpty {
            // Fallback: use user's average or neutral
            let userAvg = relevantScores.isEmpty ? 6.0 : relevantScores.map { Double($0.display100) / 10.0 }.reduce(0, +) / Double(relevantScores.count)
            finalScore = userAvg
            topReasons = ["Based on your typical ratings"]
        } else {
            // Sort by weight - strongest signals first
            let sortedPredictions = predictions.sorted { $0.weight > $1.weight }

            // Use weighted average but with exponential emphasis on top predictions
            var totalWeight = 0.0
            var weightedSum = 0.0

            for (idx, pred) in sortedPredictions.enumerated() {
                // Top predictions get bonus weight
                let positionBoost = idx < 2 ? 1.5 : 1.0
                let effectiveWeight = pred.weight * positionBoost
                weightedSum += pred.score * effectiveWeight
                totalWeight += effectiveWeight
            }

            finalScore = weightedSum / totalWeight

            // AMPLIFY strong signals - if top prediction deviates significantly, follow it more
            if let strongest = sortedPredictions.first, strongest.weight >= 3.0 {
                let deviation = strongest.score - finalScore
                // Strong genre/talent matches should pull score more aggressively
                finalScore += deviation * 0.5
            }

            // Add variety based on prediction spread
            let predScores = sortedPredictions.map { $0.score }
            let spread = (predScores.max() ?? 6.0) - (predScores.min() ?? 6.0)
            if spread > 2.0 {
                // High disagreement - lean toward strongest signal more
                if let strongest = sortedPredictions.first {
                    finalScore = finalScore * 0.6 + strongest.score * 0.4
                }
            }

            topReasons = sortedPredictions.prefix(3).map { $0.reason }
            debugInfo += " | Top: \(sortedPredictions.first?.reason ?? "none"): \(String(format: "%.1f", sortedPredictions.first?.score ?? 0))"
        }

        // Calculate confidence based on data quality
        let dataPoints = relevantScores.count + (genrePrediction != nil ? 1 : 0) + (talentPrediction != nil ? 1 : 0)
        let confidence = min(Double(dataPoints) / 8.0, 0.9)

        // Clamp to valid range
        finalScore = min(max(finalScore, 1.0), 10.0)

        return PredictionExplanation(
            score: finalScore,
            confidence: confidence,
            reasons: topReasons,
            debugInfo: debugInfo
        )
    }

    /// Add movie attributes with custom weight
    private func addMovieAttributesWeighted(
        movie: Movie,
        rating: Double,
        weight: Double,
        to attributeScores: inout [String: [Double]]
    ) {
        // Apply weight by adding multiple copies (simple approximation)
        let copies = max(1, Int(weight * 2))
        for _ in 0..<copies {
            addMovieAttributes(movie: movie, rating: rating, to: &attributeScores)
        }
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
        var genreScores: [(score: Double, weight: Double)] = []
        var matchedGenres: [String] = []

        for genreID in movie.genreIDs {
            let key = "genre:\(genreID)"
            if let scores = attributeScores[key], !scores.isEmpty {
                let avg = scores.reduce(0, +) / Double(scores.count)
                // Calculate variance to understand consistency
                let variance = scores.map { pow($0 - avg, 2) }.reduce(0, +) / Double(scores.count)
                // Lower variance = more consistent = higher weight
                let consistencyWeight = variance < 1.0 ? 1.5 : 1.0
                genreScores.append((avg, consistencyWeight * Double(scores.count)))
                matchedGenres.append(genreIDToString(genreID))
            }
        }

        // Also check genre combos (STRONG signal)
        if movie.genreIDs.count >= 2 {
            let sorted = movie.genreIDs.sorted()
            for i in 0..<sorted.count {
                for j in (i+1)..<sorted.count {
                    let key = "combo:\(sorted[i])-\(sorted[j])"
                    if let scores = attributeScores[key], !scores.isEmpty {
                        let avg = scores.reduce(0, +) / Double(scores.count)
                        // Combo matches are VERY strong signals - triple weight
                        genreScores.append((avg, 3.0 * Double(scores.count)))
                    }
                }
            }
        }

        guard !genreScores.isEmpty else { return nil }

        // Weighted average by sample count and consistency
        let totalWeight = genreScores.reduce(0.0) { $0 + $1.weight }
        let weightedSum = genreScores.reduce(0.0) { $0 + ($1.score * $1.weight) }
        var avgScore = weightedSum / totalWeight

        // Boost extreme scores - if user loves/hates a genre, lean into it
        let maxGenreScore = genreScores.map { $0.score }.max() ?? avgScore
        let minGenreScore = genreScores.map { $0.score }.min() ?? avgScore

        if maxGenreScore > 8.0 && maxGenreScore - avgScore > 1.0 {
            // Strong positive signal - boost toward max
            avgScore = avgScore * 0.6 + maxGenreScore * 0.4
        } else if minGenreScore < 4.0 && avgScore - minGenreScore > 1.0 {
            // Strong negative signal - pull toward min
            avgScore = avgScore * 0.6 + minGenreScore * 0.4
        }

        let dataPoints = genreScores.count
        let confidence = min(Double(dataPoints) / 4.0, 1.0)
        let reason = matchedGenres.isEmpty ? "Genre match" : "Matches: " + matchedGenres.prefix(2).joined(separator: ", ")

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
