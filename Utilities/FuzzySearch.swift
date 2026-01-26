// FuzzySearch.swift
// Provides typo-tolerant search suggestions using Levenshtein distance

import Foundation

struct FuzzySearch {

    /// Calculate the Levenshtein distance between two strings
    static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1.lowercased())
        let s2 = Array(s2.lowercased())

        let m = s1.count
        let n = s2.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = s1[i - 1] == s2[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }

        return matrix[m][n]
    }

    /// Calculate similarity score between two strings (0.0 to 1.0)
    static func similarity(_ s1: String, _ s2: String) -> Double {
        let distance = levenshteinDistance(s1, s2)
        let maxLen = max(s1.count, s2.count)
        if maxLen == 0 { return 1.0 }
        return 1.0 - (Double(distance) / Double(maxLen))
    }

    /// Check if query is a fuzzy match for title (allows for typos)
    static func isFuzzyMatch(query: String, title: String, threshold: Double = 0.7) -> Bool {
        let query = query.lowercased()
        let title = title.lowercased()

        // Exact substring match
        if title.contains(query) { return true }

        // Check if query matches start of title
        let titlePrefix = String(title.prefix(query.count + 2))
        if similarity(query, titlePrefix) >= threshold { return true }

        // Check word-by-word matching
        let titleWords = title.split(separator: " ").map(String.init)
        for word in titleWords {
            if similarity(query, word) >= threshold { return true }
        }

        // Full similarity check for short queries
        if query.count <= 10 && similarity(query, title) >= threshold * 0.8 {
            return true
        }

        return false
    }

    /// Find suggestions from a list of titles based on fuzzy matching
    static func findSuggestions(
        query: String,
        in titles: [String],
        maxResults: Int = 5,
        minSimilarity: Double = 0.5
    ) -> [String] {
        guard !query.isEmpty else { return [] }

        let scored = titles.map { title -> (String, Double) in
            let sim = similarity(query, title)
            // Boost score if title starts with query
            let boost = title.lowercased().hasPrefix(query.lowercased()) ? 0.3 : 0.0
            return (title, min(sim + boost, 1.0))
        }

        return scored
            .filter { $0.1 >= minSimilarity }
            .sorted { $0.1 > $1.1 }
            .prefix(maxResults)
            .map { $0.0 }
    }

    /// Generate "Did you mean?" suggestions based on common movie titles
    static func didYouMean(query: String, knownTitles: [String]) -> String? {
        guard query.count >= 3 else { return nil }

        var bestMatch: (title: String, score: Double)? = nil

        for title in knownTitles {
            let score = similarity(query, title)
            // Only suggest if it's close but not exact
            if score >= 0.6 && score < 1.0 {
                if bestMatch == nil || score > bestMatch!.score {
                    bestMatch = (title, score)
                }
            }
        }

        return bestMatch?.title
    }
}

// MARK: - Common Movie Title Suggestions
extension FuzzySearch {
    /// Popular movie titles for quick suggestions
    static let popularTitles: [String] = [
        "The Shawshank Redemption",
        "The Godfather",
        "The Dark Knight",
        "Pulp Fiction",
        "Forrest Gump",
        "Inception",
        "The Matrix",
        "Interstellar",
        "Fight Club",
        "Goodfellas",
        "The Avengers",
        "Spider-Man",
        "Batman",
        "Superman",
        "Star Wars",
        "Harry Potter",
        "Lord of the Rings",
        "Jurassic Park",
        "Titanic",
        "Avatar",
        "The Lion King",
        "Toy Story",
        "Finding Nemo",
        "Frozen",
        "Despicable Me",
        "Minions",
        "Shrek",
        "Inside Out",
        "Coco",
        "Moana",
        "Encanto",
        "Oppenheimer",
        "Barbie",
        "John Wick",
        "Top Gun",
        "Mission Impossible",
        "Fast and Furious",
        "Transformers",
        "Pirates of the Caribbean"
    ]
}
