// ImportService.swift
// REPLACE your ImportService.swift with this version
// Adds badge calculation after import

import Foundation
import SwiftData
import Combine

@MainActor
final class ImportService: ObservableObject {

    static let shared = ImportService()
    private init() {}

    @Published private(set) var isRunning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var message: String = "Idle"
    @Published private(set) var errors: [String] = []
    @Published private(set) var lastImportIDs: [UUID] = []
    @Published var syncAfterImport: Bool = false

    private lazy var api: TMDbClient = { try! TMDbClient() }()

    func runImport(data: Data, context: ModelContext) async {
        guard !isRunning else { return }
        isRunning = true
        progress = 0
        message = "Parsing..."
        errors.removeAll()
        lastImportIDs.removeAll()
        defer { isRunning = false }

        let csvString = String(decoding: data, as: UTF8.self)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("import.csv")
        try? csvString.write(to: tempURL, atomically: true, encoding: .utf8)
        
        var rows: [CSVManager.ImportedRow] = []
        do { rows = try CSVManager.parseCSV(url: tempURL) }
        catch { errors.append("CSV Error: \(error.localizedDescription)"); isRunning = false; return }
        
        // Deduplicate Rows (Netflix often has 100 entries for "The Office")
        let uniqueRows = Array(Set(rows.map { $0.title })).map { title in
            rows.first(where: { $0.title == title })!
        }
        
        let owner: String = (try? await AuthService.shared.sessionActor().session().userId) ?? "guest"
        
        var importedCount = 0
        var duplicateCount = 0

        // 2. Process Rows
        for (i, row) in uniqueRows.enumerated() {
            message = "Processing \(i + 1)/\(uniqueRows.count): \(row.title)"
            progress = Double(i + 1) / Double(max(uniqueRows.count, 1))

            do {
                let page = try await api.searchMulti(query: row.title)
                
                let match = page.results.first { tm in
                    guard let y = row.year, let tmY = tm.year else { return true }
                    return abs(y - tmY) <= 1
                } ?? page.results.first
                
                if let tm = match {
                    // CHECK IF ALREADY EXISTS IN LIBRARY
                    let tmdbID = tm.id
                    let allMovies = (try? context.fetch(FetchDescriptor<Movie>())) ?? []

                    if allMovies.first(where: { $0.tmdbID == tmdbID }) != nil {
                        // MOVIE EXISTS -> SKIP (Prevent Duplicate)
                        duplicateCount += 1
                        continue
                    }
                    
                    // NEW MOVIE -> CREATE
                    importedCount += 1
                    let genres = tm.genreIds ?? []
                    let new = Movie(
                        title: tm.displayTitle,
                        year: tm.year,
                        tmdbID: tm.id,
                        posterPath: tm.posterPath,
                        genreIDs: genres,
                        tags: tm.tags ?? [],
                        mediaType: tm.mediaType ?? "movie",
                        ownerId: owner
                    )
                    context.insert(new)
                    
                    // Add to Seen
                    context.insert(UserItem(movie: new, state: .seen, ownerId: owner))
                    
                    // Add LogEntry with date if available
                    let log = LogEntry(
                        createdAt: row.date ?? Date(),
                        rating: nil,
                        watchedOn: row.date,
                        whereWatched: nil,
                        withWho: nil,
                        notes: nil,
                        movie: new,
                        ownerId: owner
                    )
                    context.insert(log)
                    
                    // Add Score if available
                    if let rating = row.rating {
                        let score = Score(movieID: new.id, display100: rating, latent: 0, variance: 0, ownerId: owner)
                        context.insert(score)
                    }
                    
                    lastImportIDs.append(new.id)
                    try? await Task.sleep(nanoseconds: 250_000_000) // Rate limit
                }
            } catch {
                errors.append("Error: \(row.title)")
            }
        }
        
        try? context.save()
        
        // NEW: Calculate badges after import
        message = "Calculating badges..."
        calculateBadges(context: context)
        
        // Final Status Message
        message = "Done! Imported \(importedCount) new items. Skipped \(duplicateCount) duplicates. Badges updated!"
        
        // Keep message visible for a moment
        try? await Task.sleep(nanoseconds: 3_000_000_000)
    }
    
    // NEW: Badge calculation function
    private func calculateBadges(context: ModelContext) {
        let descriptor = FetchDescriptor<LogEntry>()
        
        guard let allLogs = try? context.fetch(descriptor) else { return }
        
        let inputs = allLogs.compactMap { log -> BadgeInput? in
            guard let movie = log.movie else { return nil }
            return BadgeInput(watchedOn: log.watchedOn, genreIDs: movie.genreIDs)
        }
        
        BadgeService.shared.calculateBadges(inputs: inputs)
        print("✅ Badges recalculated after import - \(inputs.count) logs processed")
    }
}
