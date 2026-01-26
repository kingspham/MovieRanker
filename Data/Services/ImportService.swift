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

    // If API key is missing, fail fast in dev instead of silently ignoring
    private lazy var api: TMDbClient = { try! TMDbClient() }()

    func runImport(data: Data, context: ModelContext) async {
        guard !isRunning else { return }
        isRunning = true
        progress = 0
        message = "Parsing…"
        errors.removeAll()
        lastImportIDs.removeAll()
        defer { isRunning = false; message = "Done" }

        // 1) Data → String
        let csvString = String(decoding: data, as: UTF8.self)

        // 2) Parse CSV
        let table = CSV.parse(csvString)
        guard let summary = ImportDetector.detect(table: table) else {
            errors.append("Could not detect format.")
            return
        }
        let rows = ImportDetector.mapRows(table: table, format: summary.detected)

        // Consistent owner id for all inserts
        let owner = SessionManager.shared.userId ?? "guest"

        // Local cache by normalized title#year
        var cache = Dictionary(uniqueKeysWithValues:
            self.fetchAll(Movie.self, context: context).map { (Self.key($0.title, $0.year), $0) }
        )

        // 3) Rows
        for (i, row) in rows.enumerated() {
            message = "Importing \(i + 1)/\(rows.count)…"
            progress = Double(i + 1) / Double(max(rows.count, 1))

            let title = row.title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            var target = cache[Self.key(title, row.year)]

            // If still unfound, query TMDb
            if target == nil {
                do {
                    let page = try await api.searchMovies(query: title)
                    let match = page.results.first { tm in
                        guard let y = row.year else { return true }
                        return tm.year == y
                    } ?? page.results.first

                    if let tm = match {
                        let new = Movie(
                            title: tm.title,
                            year: tm.year,
                            tmdbID: tm.id,
                            posterPath: tm.posterPath,
                            genreIDs: tm.genreIDs,
                            ownerId: owner
                        )
                        context.insert(new)
                        target = new
                        cache[Self.key(new.title, new.year)] = new
                        lastImportIDs.append(new.id)
                    }
                } catch {
                    errors.append("TMDb lookup failed for \"\(title)\": \(error.localizedDescription)")
                }
            }

            // Create minimal movie when not found anywhere
            if target == nil {
                let new = Movie(title: title, year: row.year, ownerId: owner)
                context.insert(new)
                target = new
                cache[Self.key(new.title, new.year)] = new
                lastImportIDs.append(new.id)
            }

            guard let movie = target else { continue }

            // De-duplicated log insert
            if let date = row.watchedOn {
                let existingLogs: [LogEntry] = self.fetchAll(context: context)
                let dayKeyValue = Self.dayKeyString(from: date)
                let dupe = existingLogs.first { le in
                    guard let leDate = le.watchedOn else { return false }
                    let leDayKey = Self.dayKeyString(from: leDate)
                    return le.movie?.id == movie.id &&
                           leDayKey == dayKeyValue &&
                           (le.notes == row.notes)
                }
                if dupe == nil {
                    let log = LogEntry(
                        createdAt: Date(),
                        rating: nil,
                        watchedOn: row.watchedOn,
                        whereWatched: nil,
                        withWho: nil,
                        notes: row.notes,
                        labels: row.labels,
                        movie: movie,
                        show: nil,
                        ownerId: owner
                    )
                    context.insert(log)
                }
            }

            // Ensure Score exists
            let scores: [Score] = self.fetchAll(context: context)
            if scores.first(where: { $0.movieID == movie.id }) == nil {
                let newScore = Score(
                    movieID: movie.id,
                    display100: 50,
                    latent: 0.0,
                    variance: 1.0,
                    ownerId: owner
                )
                context.insert(newScore)
            }

            // Ensure Seen marker
            let items: [UserItem] = self.fetchAll(context: context)
            if items.first(where: { $0.movie?.id == movie.id && $0.state == .seen }) == nil {
                let newItem = UserItem(
                    movie: movie,
                    show: nil,
                    state: .seen,
                    ownerId: owner
                )
                context.insert(newItem)
            }

            do { try context.save() } catch {
                errors.append("Save failed for \"\(title)\": \(error.localizedDescription)")
            }
        }
    }

    func undoLastImport(context: ModelContext) {
        guard !lastImportIDs.isEmpty else { return }
        let movies: [Movie] = fetchAll(context: context)
        for id in lastImportIDs {
            if let m = movies.first(where: { $0.id == id }) {
                context.delete(m)
            }
        }
        SD.save(context)
        lastImportIDs.removeAll()
    }

    private static func key(_ title: String, _ year: Int?) -> String {
        let t = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let y = year { return "\(t)#\(y)" }
        return t
    }
    
    private static func dayKeyString(from date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type = T.self, context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }
}

