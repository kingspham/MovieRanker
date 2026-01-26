import Foundation

// The formats we can detect from CSV headers
enum ImportFormat: Equatable {
    case letterboxd
    case trakt
    case generic
}

// A summary of what was detected and how many rows are present
struct ImportSummary: Equatable {
    let detected: ImportFormat
    let total: Int
}

// A normalized import row produced by mapping CSV rows
struct ImportRow: Equatable {
    let title: String
    let year: Int?
    let watchedOn: Date?
    let notes: String?
    let labels: [String]?
}
