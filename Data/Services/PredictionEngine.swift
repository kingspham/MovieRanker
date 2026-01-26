// PredictionEngine.swift
// IMPROVED VERSION - Better predictions with debugging

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
    
    func predict(for movie: Movie, in context: ModelContext, userId: String) -> PredictionExplanation {
        let descriptor = FetchDescriptor<Score>(predicate: #Predicate { $0.ownerId == userId })
        let userScores = (try? context.fetch(descriptor)) ?? []
        
        if userScores.isEmpty {
            return PredictionExplanation(
                score: 5.0,
                confidence: 0.1,
                reasons: ["Rank movies to start"],
                debugInfo: "No scores yet"
            )
        }
        
        // Filter to same media type (don't predict movie scores based on TV shows)
        let sameTypeScores = userScores.filter { score in
            guard let m = fetchMovie(id: score.movieID, context: context) else { return false }
            return m.mediaType == movie.mediaType
        }
        
        if sameTypeScores.isEmpty {
            return PredictionExplanation(
                score: 5.0,
                confidence: 0.2,
                reasons: ["Rank some \(movie.mediaType)s first"],
                debugInfo: "No \(movie.mediaType) scores yet"
            )
        }
        
        // Build comprehensive attribute map
        var attributeScores: [String: [Double]] = [:]
        
        for score in sameTypeScores {
            guard let rankedMovie = fetchMovie(id: score.movieID, context: context) else { continue }
            let rating = Double(score.display100) / 10.0  // Convert 1-100 to 0.1-10.0
            
            // 1. Genre attributes (primary genres)
            for genreID in rankedMovie.genreIDs {
                let key = "genre:\(genreID)"
                attributeScores[key, default: []].append(rating)
            }
            
            // 2. Genre combinations (powerful for nuance)
            if rankedMovie.genreIDs.count >= 2 {
                let sorted = rankedMovie.genreIDs.sorted()
                for i in 0..<sorted.count {
                    for j in (i+1)..<sorted.count {
                        let key = "combo:\(sorted[i])-\(sorted[j])"
                        attributeScores[key, default: []].append(rating)
                    }
                }
            }
            
            // 3. Talent attributes (directors, actors)
            for tag in rankedMovie.tags {
                if tag.starts(with: "dir:") || tag.starts(with: "actor:") {
                    attributeScores[tag, default: []].append(rating)
                }
            }
            
            // 4. Decade attribute (era preferences)
            if let year = rankedMovie.year {
                let decade = (year / 10) * 10
                let key = "decade:\(decade)"
                attributeScores[key, default: []].append(rating)
            }
            
            // 5. Year recency (do you like newer vs older stuff?)
            if let year = rankedMovie.year {
                let age = 2026 - year
                if age < 2 { attributeScores["age:new", default: []].append(rating) }
                else if age < 5 { attributeScores["age:recent", default: []].append(rating) }
                else if age < 15 { attributeScores["age:modern", default: []].append(rating) }
                else if age < 30 { attributeScores["age:classic", default: []].append(rating) }
                else { attributeScores["age:vintage", default: []].append(rating) }
            }
        }
        
        // Calculate averages for each attribute
        var attributeAverages: [String: Double] = [:]
        var attributeConfidence: [String: Double] = [:]
        
        for (key, scores) in attributeScores {
            let avg = scores.reduce(0, +) / Double(scores.count)
            attributeAverages[key] = avg
            // Confidence based on sample size (more data = more confident)
            let sampleSize = Double(scores.count)
            attributeConfidence[key] = min(sampleSize / 10.0, 1.0)  // Max confidence at 10+ samples
        }
        
        // Now predict for the target movie
        var signals: [(value: Double, weight: Double, reason: String)] = []
        
        // 1. Check genre matches
        for genreID in movie.genreIDs {
            let key = "genre:\(genreID)"
            if let avg = attributeAverages[key], let conf = attributeConfidence[key] {
                signals.append((value: avg, weight: conf * 2.0, reason: "Genre: \(genreIDToString(genreID))"))
            }
        }
        
        // 2. Check genre combos (even stronger signal!)
        if movie.genreIDs.count >= 2 {
            let sorted = movie.genreIDs.sorted()
            for i in 0..<sorted.count {
                for j in (i+1)..<sorted.count {
                    let key = "combo:\(sorted[i])-\(sorted[j])"
                    if let avg = attributeAverages[key], let conf = attributeConfidence[key] {
                        signals.append((value: avg, weight: conf * 3.0, reason: "Combo match"))
                    }
                }
            }
        }
        
        // 3. Check talent
        for tag in movie.tags {
            if let avg = attributeAverages[tag], let conf = attributeConfidence[tag] {
                if tag.starts(with: "dir:") {
                    let name = tag.replacingOccurrences(of: "dir:", with: "").replacingOccurrences(of: "_", with: " ")
                    signals.append((value: avg, weight: conf * 2.5, reason: "Director: \(name.capitalized)"))
                } else if tag.starts(with: "actor:") {
                    let name = tag.replacingOccurrences(of: "actor:", with: "").replacingOccurrences(of: "_", with: " ")
                    signals.append((value: avg, weight: conf * 1.5, reason: "Actor: \(name.capitalized)"))
                }
            }
        }
        
        // 4. Check decade
        if let year = movie.year {
            let decade = (year / 10) * 10
            let key = "decade:\(decade)"
            if let avg = attributeAverages[key], let conf = attributeConfidence[key] {
                signals.append((value: avg, weight: conf * 1.0, reason: "\(decade)s era"))
            }
        }
        
        // 5. Check age preference
        if let year = movie.year {
            let age = 2026 - year
            let ageKey: String
            if age < 2 { ageKey = "age:new" }
            else if age < 5 { ageKey = "age:recent" }
            else if age < 15 { ageKey = "age:modern" }
            else if age < 30 { ageKey = "age:classic" }
            else { ageKey = "age:vintage" }
            
            if let avg = attributeAverages[ageKey], let conf = attributeConfidence[ageKey] {
                signals.append((value: avg, weight: conf * 1.0, reason: ageKey.replacingOccurrences(of: "age:", with: "").capitalized))
            }
        }
        
        // Weighted average of all signals
        var finalScore: Double
        var reasons: [String] = []
        var debugInfo = ""
        
        if !signals.isEmpty {
            // Sort by weight to get top reasons
            let sortedSignals = signals.sorted { $0.weight > $1.weight }
            
            let totalWeight = signals.reduce(0) { $0 + $1.weight }
            let weightedSum = signals.reduce(0) { $0 + ($1.value * $1.weight) }
            finalScore = weightedSum / totalWeight
            
            // Take top 2-3 reasons
            reasons = sortedSignals.prefix(3).map { $0.reason }
            
            debugInfo = "Signals: \(signals.count), Top: \(sortedSignals.prefix(3).map { "\($0.reason)(\(String(format: "%.1f", $0.value)))" }.joined(separator: ", "))"
        } else {
            // No genre/talent matches - use smarter fallback
            
            // Try using just the decade/age attributes
            var fallbackSignals: [(value: Double, weight: Double)] = []
            
            if let year = movie.year {
                let decade = (year / 10) * 10
                if let avg = attributeAverages["decade:\(decade)"] {
                    fallbackSignals.append((value: avg, weight: 1.0))
                }
                
                let age = 2026 - year
                let ageKey: String
                if age < 2 { ageKey = "age:new" }
                else if age < 5 { ageKey = "age:recent" }
                else if age < 15 { ageKey = "age:modern" }
                else if age < 30 { ageKey = "age:classic" }
                else { ageKey = "age:vintage" }
                
                if let avg = attributeAverages[ageKey] {
                    fallbackSignals.append((value: avg, weight: 1.0))
                }
            }
            
            if !fallbackSignals.isEmpty {
                let totalWeight = fallbackSignals.reduce(0) { $0 + $1.weight }
                let weightedSum = fallbackSignals.reduce(0) { $0 + ($1.value * $1.weight) }
                finalScore = weightedSum / totalWeight
                reasons = ["Based on year/decade preference"]
                debugInfo = "Fallback: Year-based prediction"
            } else {
                // Last resort - use global average
                let globalAvg = sameTypeScores.map { Double($0.display100) / 10.0 }.reduce(0, +) / Double(sameTypeScores.count)
                finalScore = globalAvg
                reasons = ["Based on your overall \(movie.mediaType) taste"]
                debugInfo = "Fallback: Global average = \(String(format: "%.1f", globalAvg))"
            }
        }
        
        // Calculate overall confidence
        let totalSignalWeight = signals.reduce(0) { $0 + $1.weight }
        let confidence = min(totalSignalWeight / 10.0, 0.95)  // Higher signals = higher confidence
        
        // Clamp to reasonable range
        finalScore = min(max(finalScore, 0.5), 9.9)
        
        // Debug info about the movie
        let genreInfo = movie.genreIDs.map { genreIDToString($0) }.joined(separator: ", ")
        let tagInfo = movie.tags.isEmpty ? "NO TAGS" : "\(movie.tags.count) tags"
        debugInfo += " | Genres: \(genreInfo) | \(tagInfo)"
        
        return PredictionExplanation(
            score: finalScore,
            confidence: confidence,
            reasons: Array(reasons.prefix(3)),
            debugInfo: debugInfo
        )
    }
    
    private func fetchMovie(id: UUID, context: ModelContext) -> Movie? {
        let desc = FetchDescriptor<Movie>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(desc))?.first
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
