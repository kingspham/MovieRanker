// WatchLocation.swift
import Foundation

enum WatchLocation: String, CaseIterable, Codable, Sendable {
    case theater
    case home
    case airplane
    case other
    case notSure

    var displayName: String {
        switch self {
        case .theater: return "Theater"
        case .home: return "Home"
        case .airplane: return "Airplane"
        case .other: return "Other"
        case .notSure: return "Not Sure"
        }
    }
}
