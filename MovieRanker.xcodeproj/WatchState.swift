import Foundation

public enum WatchState: String, Codable, CaseIterable, Equatable {
    case seen
    case watchlist
    case inProgress = "in_progress"
    case abandoned
}

extension WatchState: Sendable {}
