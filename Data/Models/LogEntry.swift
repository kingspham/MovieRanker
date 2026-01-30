// LogEntry.swift
// UPDATED - Added reading tracker fields for books + book format

import Foundation
import SwiftData

// Book format enum
enum BookFormat: String, Codable, CaseIterable {
    case physical = "Physical"
    case ebook = "E-Reader"
    case audiobook = "Audiobook"
    case notSure = "Not Sure"
}

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

    // Book format (physical, e-reader, audiobook)
    var bookFormat: BookFormat?

    // Social tagging - IDs of users who watched/read with you
    var taggedUserIds: [String]?

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
        finishedReading: Date? = nil,
        bookFormat: BookFormat? = nil,
        taggedUserIds: [String]? = nil
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
        self.bookFormat = bookFormat
        self.taggedUserIds = taggedUserIds
    }

    // Computed property for reading duration
    var readingDuration: Int? {
        guard let start = startedReading, let finish = finishedReading else { return nil }
        return Calendar.current.dateComponents([.day], from: start, to: finish).day
    }
}
