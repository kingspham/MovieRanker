// LogEntry.swift
// UPDATED - Added reading tracker fields for books

import Foundation
import SwiftData

@Model
final class LogEntry {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var rating: Double?
    var watchedOn: Date?
    var whereWatched: WatchLocation?
    var withWho: String?
    var notes: String?
    var labels: [String]?
    var movie: Movie?
    var ownerId: String
    
    // Reading Tracker (for books)
    var startedReading: Date?
    var finishedReading: Date?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        rating: Double? = nil,
        watchedOn: Date? = nil,
        whereWatched: WatchLocation? = nil,
        withWho: String? = nil,
        notes: String? = nil,
        labels: [String]? = nil,
        movie: Movie? = nil,
        ownerId: String,
        startedReading: Date? = nil,
        finishedReading: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rating = rating
        self.watchedOn = watchedOn
        self.whereWatched = whereWatched
        self.withWho = withWho
        self.notes = notes
        self.labels = labels
        self.movie = movie
        self.ownerId = ownerId
        self.startedReading = startedReading
        self.finishedReading = finishedReading
    }
    
    // Computed property for reading duration
    var readingDuration: Int? {
        guard let start = startedReading, let finish = finishedReading else { return nil }
        return Calendar.current.dateComponents([.day], from: start, to: finish).day
    }
}
