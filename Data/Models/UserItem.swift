import Foundation
import SwiftData

@Model
final class UserItem {
    @Attribute(.unique) var id: UUID
    var ownerId: String
    var createdAt: Date
    var updatedAt: Date
    var state: State
    
    // Matches the inverse in Movie.swift
    var movie: Movie?

    init(movie: Movie?, state: State, ownerId: String) {
        self.id = UUID()
        self.movie = movie
        self.state = state
        self.ownerId = ownerId
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    enum State: String, Codable, CaseIterable {
        case seen
        case watchlist
        case favorite
    }
}
