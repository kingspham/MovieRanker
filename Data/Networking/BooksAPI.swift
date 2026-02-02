// BooksAPI.swift
// USING OPEN LIBRARY API - No quotas, no API key needed!

import Foundation

// MARK: - Open Library DTOs
struct OpenLibraryResponse: Decodable {
    let docs: [OpenLibraryDoc]?
}

struct OpenLibraryDoc: Decodable {
    let key: String
    let title: String
    let author_name: [String]?
    let first_publish_year: Int?
    let isbn: [String]?
    let cover_i: Int?
    let subject: [String]?
    let publisher: [String]?

    enum CodingKeys: String, CodingKey {
        case key, title, isbn, subject, publisher
        case author_name = "author_name"
        case first_publish_year = "first_publish_year"
        case cover_i = "cover_i"
    }
}

// MARK: - Client
actor BooksAPI {
    private let session = URLSession.shared
    private let baseUrl = "https://openlibrary.org/search.json"

    func searchBooks(query: String) async throws -> [TMDbItem] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseUrl)?q=\(encoded)&limit=20") else {
            print("📚 BooksAPI: Invalid URL for query: \(query)")
            return []
        }

        print("📚 BooksAPI: Searching Open Library for '\(query)'...")

        do {
            let (data, response) = try await session.data(from: url)

            // Check HTTP response
            if let httpResponse = response as? HTTPURLResponse {
                print("📚 BooksAPI: HTTP Status: \(httpResponse.statusCode)")

                if httpResponse.statusCode != 200 {
                    print("📚 BooksAPI: Error response: \(String(data: data, encoding: .utf8) ?? "unknown")")
                    return []
                }
            }

            let bookResponse = try JSONDecoder().decode(OpenLibraryResponse.self, from: data)

            guard let docs = bookResponse.docs, !docs.isEmpty else {
                print("📚 BooksAPI: No books found for '\(query)'")
                return []
            }

            print("📚 BooksAPI: Found \(docs.count) books")

            let results = docs.compactMap { doc -> TMDbItem? in
                // Build cover URL if available
                var posterPath: String? = nil
                if let coverId = doc.cover_i {
                    posterPath = "https://covers.openlibrary.org/b/id/\(coverId)-L.jpg"
                }

                // Combine authors and subjects for tags
                var tags: [String] = []
                if let authors = doc.author_name {
                    tags.append(contentsOf: authors)
                }
                if let subjects = doc.subject?.prefix(3) {
                    tags.append(contentsOf: subjects)
                }

                // Create a stable numeric ID from the key
                let id = abs(doc.key.hashValue)

                // Format year as release date
                let releaseDate = doc.first_publish_year.map { "\($0)-01-01" }

                return TMDbItem(
                    id: id,
                    title: doc.title,
                    overview: nil, // Open Library doesn't provide descriptions in search
                    releaseDate: releaseDate,
                    posterPath: posterPath,
                    genreIds: [],
                    tags: tags.isEmpty ? nil : tags,
                    mediaType: "book",
                    popularity: nil
                )
            }

            print("📚 BooksAPI: Returning \(results.count) book results")
            return results

        } catch {
            print("📚 BooksAPI Error: \(error)")
            return []
        }
    }

    /// Get trending/popular books by searching for well-known subjects
    func getTrendingBooks() async throws -> [TMDbItem] {
        // Search for popular genres/subjects to simulate trending
        let trendingSubjects = ["bestseller", "fiction", "thriller"]
        var allBooks: [TMDbItem] = []

        for subject in trendingSubjects {
            guard let url = URL(string: "https://openlibrary.org/search.json?subject=\(subject)&limit=8&sort=rating") else {
                continue
            }

            do {
                let (data, _) = try await session.data(from: url)
                let bookResponse = try JSONDecoder().decode(OpenLibraryResponse.self, from: data)

                if let docs = bookResponse.docs {
                    let results = docs.prefix(5).compactMap { doc -> TMDbItem? in
                        guard let coverId = doc.cover_i else { return nil } // Only include books with covers
                        let posterPath = "https://covers.openlibrary.org/b/id/\(coverId)-L.jpg"

                        var tags: [String] = []
                        if let authors = doc.author_name {
                            tags.append(contentsOf: authors)
                        }

                        let id = abs(doc.key.hashValue)
                        let releaseDate = doc.first_publish_year.map { "\($0)-01-01" }

                        return TMDbItem(
                            id: id,
                            title: doc.title,
                            overview: nil,
                            releaseDate: releaseDate,
                            posterPath: posterPath,
                            genreIds: [],
                            tags: tags.isEmpty ? nil : tags,
                            mediaType: "book",
                            popularity: Double(doc.cover_i ?? 0)
                        )
                    }
                    allBooks.append(contentsOf: results)
                }
            } catch {
                print("📚 BooksAPI: Error fetching subject \(subject): \(error)")
            }
        }

        // Remove duplicates and return top 10
        var seen = Set<Int>()
        return allBooks.filter { book in
            if seen.contains(book.id) { return false }
            seen.insert(book.id)
            return true
        }.prefix(10).map { $0 }
    }
}
