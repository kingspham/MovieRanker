import Foundation
import SwiftData

extension Movie {
    /// Safely finds an existing movie/book/podcast or creates a new one from a TMDbItem.
    /// This prevents duplicate entries and thread crashes.
    @MainActor
    static func findOrCreate(from item: TMDbItem, type: String, context: ModelContext, ownerId: String) -> Movie {
        // 1. Try to find existing by TMDb ID (for visual media) or Hash (for others)
        let targetID = item.id
        let predicate = #Predicate<Movie> { $0.tmdbID == targetID }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        
        // 2. Create New
        let newItem = Movie(
            title: item.displayTitle,
            year: item.year,
            tmdbID: item.id,
            posterPath: item.posterPath,
            genreIDs: item.genreIds ?? [],
            tags: item.tags ?? [],
            mediaType: type,
            ownerId: ownerId
        )
        
        // Custom Logic for Books/Podcasts authors which are stored in tags
        if (type == "book" || type == "podcast"), let author = item.tags?.first {
            newItem.authors = [author]
        }
        
        context.insert(newItem)
        
        // Save immediately to ensure ID is stable
        try? context.save()
        
        return newItem
    }
}
