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
        // PERFORMANCE FIX: Fetch all data ONCE and use dictionaries for O(1) lookups
        let allScoresDescriptor = FetchDescriptor<Score>()
        let allScores = (try? context.fetch(allScoresDescriptor)) ?? []
        let userScores = allScores.filter { $0.ownerId == userId || $0.ownerId == "guest" }

        let allLogsDescriptor = FetchDescriptor<LogEntry>()
        let allLogs = (try? context.fetch(allLogsDescriptor)) ?? []
        let userLogs = allLogs.filter { $0.ownerId == userId || $0.ownerId == "guest" }

        // CRITICAL: Fetch all movies ONCE and create lookup dictionary
        let allMoviesDescriptor = FetchDescriptor<Movie>()
        let allMovies = (try? context.fetch(allMoviesDescriptor)) ?? []
        let movieLookup = Dictionary(uniqueKeysWithValues: allMovies.map { ($0.id, $0) })

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

        // Process explicit scores - use lookup instead of repeated fetches
        let sameTypeScores = userScores.filter { score in
            guard let m = movieLookup[score.movieID] else { return false }
            return m.mediaType == movie.mediaType
        }

        // Also get cross-type scores for genre learning - use lookup
        let allUserScoresWithMovies = userScores.compactMap { score -> (Score, Movie)? in
            guard let m = movieLookup[score.movieID] else { return nil }
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

        // METHOD 4: Keywords/theme matching (STRONG signal)
        let keywordPrediction = predictByKeywords(movie: movie, attributeScores: attributeScores)
        if let kp = keywordPrediction {
            predictions.append((kp.score, kp.confidence * 3.5, kp.reason))
        }

        // METHOD 5: Runtime preference
        let runtimePrediction = predictByRuntime(movie: movie, attributeScores: attributeScores)
        if let rp = runtimePrediction {
            predictions.append((rp.score, rp.confidence * 1.5, rp.reason))
        }

        // METHOD 6: Origin/language preference
        let originPrediction = predictByOrigin(movie: movie, attributeScores: attributeScores)
        if let op = originPrediction {
            predictions.append((op.score, op.confidence * 2.0, op.reason))
        }

        // METHOD 7: Popularity preference (mainstream vs indie)
        let popularityPrediction = predictByPopularity(movie: movie, attributeScores: attributeScores)
        if let pp = popularityPrediction {
            predictions.append((pp.score, pp.confidence * 1.2, pp.reason))
        }

        // METHOD 8: TMDb user rating signal
        let tmdbPrediction = predictByTMDbRating(movie: movie, attributeScores: attributeScores)
        if let tp = tmdbPrediction {
            predictions.append((tp.score, tp.confidence * 1.0, tp.reason))
        }

        // METHOD 9: User's average rating bias (personalized baseline)
        let relevantScores = sameTypeScores.isEmpty ? userScores : sameTypeScores
        if !relevantScores.isEmpty {
            let scores = relevantScores.map { Double($0.display100) / 10.0 }
            let userAvg = scores.reduce(0, +) / Double(scores.count)
            let userStdDev = sqrt(scores.map { pow($0 - userAvg, 2) }.reduce(0, +) / Double(scores.count))

            // User baseline is their average with some variance consideration
            let baselineScore = userAvg + (userStdDev > 1.0 ? 0.0 : 0.5) // Harsh raters get slight boost
            predictions.append((baselineScore, 1.0, "Your rating style"))
        }

        // METHOD 10: Critic score (lower weight - user prefs matter more)
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

    /// Predict based on content keywords/themes
    private func predictByKeywords(movie: Movie, attributeScores: [String: [Double]]) -> (score: Double, confidence: Double, reason: String)? {
        guard let keywords = movie.keywords, !keywords.isEmpty else { return nil }

        var keywordScores: [(score: Double, keyword: String, weight: Double)] = []

        for keyword in keywords {
            let key = "keyword:\(keyword.lowercased())"
            if let scores = attributeScores[key], !scores.isEmpty {
                let avg = scores.reduce(0, +) / Double(scores.count)
                // More samples = higher confidence
                keywordScores.append((avg, keyword, Double(scores.count)))
            }
        }

        guard !keywordScores.isEmpty else { return nil }

        // Weighted average by sample count
        let totalWeight = keywordScores.reduce(0.0) { $0 + $1.weight }
        let weightedSum = keywordScores.reduce(0.0) { $0 + ($1.score * $1.weight) }
        let avgScore = weightedSum / totalWeight

        let matchedCount = keywordScores.count
        let confidence = min(Double(matchedCount) / 3.0, 1.0)

        // Use top matching keyword for reason
        let topKeyword = keywordScores.sorted { $0.weight > $1.weight }.first?.keyword ?? "themes"
        let reason = matchedCount > 2 ? "Theme match (\(matchedCount) keywords)" : "Theme: \(topKeyword)"

        return (avgScore, confidence, reason)
    }

    /// Predict based on runtime preference
    private func predictByRuntime(movie: Movie, attributeScores: [String: [Double]]) -> (score: Double, confidence: Double, reason: String)? {
        guard let runtime = movie.runtime, runtime > 0 else { return nil }

        // Categorize runtime into buckets
        let runtimeKey: String
        let runtimeLabel: String
        if runtime < 90 {
            runtimeKey = "runtime:short"
            runtimeLabel = "Short film"
        } else if runtime < 120 {
            runtimeKey = "runtime:standard"
            runtimeLabel = "Standard length"
        } else if runtime < 150 {
            runtimeKey = "runtime:long"
            runtimeLabel = "Long film"
        } else {
            runtimeKey = "runtime:epic"
            runtimeLabel = "Epic length"
        }

        guard let scores = attributeScores[runtimeKey], !scores.isEmpty else { return nil }

        let avgScore = scores.reduce(0, +) / Double(scores.count)
        let confidence = min(Double(scores.count) / 5.0, 0.7)

        return (avgScore, confidence, runtimeLabel)
    }

    /// Predict based on country/language of origin
    private func predictByOrigin(movie: Movie, attributeScores: [String: [Double]]) -> (score: Double, confidence: Double, reason: String)? {
        var originScores: [(score: Double, label: String, weight: Double)] = []

        // Check original language
        if let lang = movie.originalLanguage {
            let langKey = "lang:\(lang)"
            if let scores = attributeScores[langKey], !scores.isEmpty {
                let avg = scores.reduce(0, +) / Double(scores.count)
                let langLabel = languageCodeToName(lang)
                originScores.append((avg, langLabel, Double(scores.count) * 1.5)) // Language weighted higher
            }
        }

        // Check production countries
        if let countries = movie.productionCountries {
            for country in countries {
                let countryKey = "country:\(country)"
                if let scores = attributeScores[countryKey], !scores.isEmpty {
                    let avg = scores.reduce(0, +) / Double(scores.count)
                    originScores.append((avg, countryCodeToName(country), Double(scores.count)))
                }
            }
        }

        guard !originScores.isEmpty else { return nil }

        let totalWeight = originScores.reduce(0.0) { $0 + $1.weight }
        let weightedSum = originScores.reduce(0.0) { $0 + ($1.score * $1.weight) }
        let avgScore = weightedSum / totalWeight

        let confidence = min(Double(originScores.count) / 3.0, 0.8)
        let topMatch = originScores.sorted { $0.weight > $1.weight }.first?.label ?? "International"

        return (avgScore, confidence, topMatch)
    }

    /// Predict based on mainstream vs indie preference (using popularity and vote count)
    private func predictByPopularity(movie: Movie, attributeScores: [String: [Double]]) -> (score: Double, confidence: Double, reason: String)? {
        guard let popularity = movie.popularity else { return nil }

        // Categorize by popularity tier
        let popKey: String
        let popLabel: String
        if popularity > 100 {
            popKey = "popularity:blockbuster"
            popLabel = "Blockbuster"
        } else if popularity > 30 {
            popKey = "popularity:mainstream"
            popLabel = "Mainstream"
        } else if popularity > 10 {
            popKey = "popularity:moderate"
            popLabel = "Moderate buzz"
        } else {
            popKey = "popularity:indie"
            popLabel = "Under the radar"
        }

        guard let scores = attributeScores[popKey], !scores.isEmpty else { return nil }

        let avgScore = scores.reduce(0, +) / Double(scores.count)
        let confidence = min(Double(scores.count) / 5.0, 0.6)

        return (avgScore, confidence, popLabel)
    }

    /// Predict using TMDb community ratings as a signal
    private func predictByTMDbRating(movie: Movie, attributeScores: [String: [Double]]) -> (score: Double, confidence: Double, reason: String)? {
        guard let voteAvg = movie.voteAverage, let voteCount = movie.voteCount,
              voteCount > 50 else { return nil } // Need enough votes for meaningful signal

        // Categorize by TMDb rating tier
        let ratingKey: String
        let ratingLabel: String
        if voteAvg >= 8.0 {
            ratingKey = "tmdb:excellent"
            ratingLabel = "Highly rated"
        } else if voteAvg >= 7.0 {
            ratingKey = "tmdb:good"
            ratingLabel = "Well received"
        } else if voteAvg >= 6.0 {
            ratingKey = "tmdb:average"
            ratingLabel = "Mixed reviews"
        } else {
            ratingKey = "tmdb:poor"
            ratingLabel = "Poorly rated"
        }

        // Check if user aligns with TMDb consensus
        if let scores = attributeScores[ratingKey], !scores.isEmpty {
            let avgScore = scores.reduce(0, +) / Double(scores.count)
            let confidence = min(Double(scores.count) / 6.0, 0.5) // Lower confidence - this is secondary signal
            return (avgScore, confidence, ratingLabel)
        }

        // Fallback: use TMDb rating directly but adjusted by user bias
        if let userBiasScores = attributeScores["tmdb:bias"], !userBiasScores.isEmpty {
            let userBias = userBiasScores.reduce(0, +) / Double(userBiasScores.count)
            let adjustedScore = voteAvg + (userBias - 7.0) * 0.3 // Adjust by user's deviation from average
            return (adjustedScore, 0.3, "TMDb \(String(format: "%.1f", voteAvg))")
        }

        return nil
    }

    /// Helper to convert language code to readable name
    private func languageCodeToName(_ code: String) -> String {
        switch code {
        case "en": return "English"
        case "ko": return "Korean"
        case "ja": return "Japanese"
        case "es": return "Spanish"
        case "fr": return "French"
        case "de": return "German"
        case "it": return "Italian"
        case "pt": return "Portuguese"
        case "zh": return "Chinese"
        case "hi": return "Hindi"
        case "ru": return "Russian"
        case "ar": return "Arabic"
        case "th": return "Thai"
        case "sv": return "Swedish"
        case "da": return "Danish"
        case "no": return "Norwegian"
        case "fi": return "Finnish"
        case "nl": return "Dutch"
        case "pl": return "Polish"
        case "tr": return "Turkish"
        default: return code.uppercased()
        }
    }

    /// Helper to convert country code to readable name
    private func countryCodeToName(_ code: String) -> String {
        switch code {
        case "US": return "American"
        case "GB": return "British"
        case "KR": return "Korean"
        case "JP": return "Japanese"
        case "FR": return "French"
        case "DE": return "German"
        case "IT": return "Italian"
        case "ES": return "Spanish"
        case "CA": return "Canadian"
        case "AU": return "Australian"
        case "IN": return "Indian"
        case "CN": return "Chinese"
        case "HK": return "Hong Kong"
        case "TW": return "Taiwanese"
        case "MX": return "Mexican"
        case "BR": return "Brazilian"
        case "SE": return "Swedish"
        case "DK": return "Danish"
        case "NO": return "Norwegian"
        case "NZ": return "New Zealand"
        default: return code
        }
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

        // Keywords/themes
        if let keywords = movie.keywords {
            for keyword in keywords {
                attributeScores["keyword:\(keyword.lowercased())", default: []].append(rating)
            }
        }

        // Runtime preference
        if let runtime = movie.runtime, runtime > 0 {
            if runtime < 90 {
                attributeScores["runtime:short", default: []].append(rating)
            } else if runtime < 120 {
                attributeScores["runtime:standard", default: []].append(rating)
            } else if runtime < 150 {
                attributeScores["runtime:long", default: []].append(rating)
            } else {
                attributeScores["runtime:epic", default: []].append(rating)
            }
        }

        // Language preference
        if let lang = movie.originalLanguage {
            attributeScores["lang:\(lang)", default: []].append(rating)
        }

        // Country preference
        if let countries = movie.productionCountries {
            for country in countries {
                attributeScores["country:\(country)", default: []].append(rating)
            }
        }

        // Popularity tier preference
        if let popularity = movie.popularity {
            if popularity > 100 {
                attributeScores["popularity:blockbuster", default: []].append(rating)
            } else if popularity > 30 {
                attributeScores["popularity:mainstream", default: []].append(rating)
            } else if popularity > 10 {
                attributeScores["popularity:moderate", default: []].append(rating)
            } else {
                attributeScores["popularity:indie", default: []].append(rating)
            }
        }

        // TMDb rating tier preference
        if let voteAvg = movie.voteAverage, let voteCount = movie.voteCount, voteCount > 50 {
            if voteAvg >= 8.0 {
                attributeScores["tmdb:excellent", default: []].append(rating)
            } else if voteAvg >= 7.0 {
                attributeScores["tmdb:good", default: []].append(rating)
            } else if voteAvg >= 6.0 {
                attributeScores["tmdb:average", default: []].append(rating)
            } else {
                attributeScores["tmdb:poor", default: []].append(rating)
            }
            // Also track bias for fallback calculations
            attributeScores["tmdb:bias", default: []].append(rating)
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
