import SwiftUI
import SwiftData

struct LeaderboardView: View {
    private var userId: String { SessionManager.shared.userId ?? "guest" }

    @Query private var scores: [Score]
    @Query private var movies: [Movie]
    @Query private var shows: [Show]
    @Query private var snaps: [ScoreSnapshot]

    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case movies = "Movies"
        case shows = "Shows"
        var id: String { rawValue }
    }

    init() {
        _scores = Query()           // fetch all, filter in-memory by current user
        _movies = Query()
        _shows  = Query()
        _snaps  = Query()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Only show picker if user is logged in
                if !userId.hasPrefix("guest") {
                    Picker("", selection: $filter) {
                        ForEach(Filter.allCases) { f in Text(f.rawValue).tag(f) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top)
                }

                // Movers card
                if !topMovers.isEmpty {
                    MoversCard(movers: topMovers, movies: movies, shows: shows)
                        .padding(.horizontal)
                        .padding(.top, 12)
                }

                Group {
                    let rows = resolvedRows()
                    if rows.isEmpty {
                        if userId.hasPrefix("guest") {
                            ContentUnavailableView("Sign in to see your rankings",
                                                   systemImage: "person.circle",
                                                   description: Text("Create an account or sign in to start ranking your watched movies and shows."))
                                .padding()
                        } else {
                            ContentUnavailableView("No rankings yet",
                                                   systemImage: "chart.bar",
                                                   description: Text("Mark items as watched and compare them to build your leaderboard."))
                                .padding()
                        }
                    } else {
                        List(rows.prefix(100), id: \.id) { row in
                            HStack(spacing: 12) {
                                PosterThumb(posterPath: row.posterPath, title: row.title, width: 48)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title).font(.headline)
                                    if let sub = row.subtitle { Text(sub).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Text("\(Int(row.score))")
                                    .font(.headline).monospacedDigit()
                            }
                            .padding(.vertical, 4)
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Leaderboard")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    NavigationLink(destination: CompareView(seed: nil)) {
                        Label("Continue Ranking", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
    }

    // MARK: - Resolution

    private struct Row {
        let id: UUID
        let title: String
        let subtitle: String?
        let posterPath: String?
        let score: Double
        let kind: Filter
    }

    private func resolvedRows() -> [Row] {
        let moviesByID = Dictionary(uniqueKeysWithValues: movies.map { ($0.id, $0) })
        let showsByID  = Dictionary(uniqueKeysWithValues: shows.map  { ($0.id, $0)  })

        let myScores = scores.filter { $0.ownerId == userId }

        var out: [Row] = []
        out.reserveCapacity(scores.count)

        for s in myScores {
            let id = s.movieID
            if let m = moviesByID[id], (filter == .all || filter == .movies) {
                out.append(Row(id: id, title: m.title, subtitle: m.year.map(String.init),
                               posterPath: m.posterPath, score: Double(s.display100), kind: .movies))
            } else if let sh = showsByID[id], (filter == .all || filter == .shows) {
                out.append(Row(id: id, title: sh.title, subtitle: sh.yearStart.map(String.init),
                               posterPath: sh.posterPath, score: Double(s.display100), kind: .shows))
            }
        }

        out.sort { $0.score > $1.score }
        return out
    }

    // MARK: - Movers (7 days)

    fileprivate struct Mover: Identifiable {
        let id: UUID                 // itemID
        let kind: ItemKind
        let delta: Double            // latest - earliest in 7d window
    }

    /// Top absolute movers over the last 7 days, filtered by the current segment.
    private var topMovers: [Mover] {
        let now = Date()
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now

        // Filter snaps to last 7d and current filter, and filter by ownerId
        let window = snaps
            .filter { $0.ownerId == userId }
            .filter { $0.createdAt >= sevenDaysAgo }
            .filter { snap in
                switch filter {
                case .all: return true
                case .movies: return snap.kind == .movie
                case .shows: return snap.kind == .show
                }
            }

        // Group by itemID, compute delta = latest - earliest
        var byItem: [UUID: (kind: ItemKind, early: Double, late: Double)] = [:]
        // We need earliest and latest per item
        let sorted = window.sorted { $0.createdAt < $1.createdAt }

        // Initialize early/late with first/last encountered in time order
        for s in sorted {
            if byItem[s.itemID] == nil {
                byItem[s.itemID] = (s.kind, s.score, s.score)
            } else {
                var cur = byItem[s.itemID]!
                cur.late = s.score
                byItem[s.itemID] = cur
            }
        }

        let movers = byItem.map { (id, tup) in
            Mover(id: id, kind: tup.kind, delta: tup.late - tup.early)
        }

        // Top 6 by absolute delta
        return movers.sorted { abs($0.delta) > abs($1.delta) }.prefix(6).map { $0 }
    }
}

// MARK: - Movers Card

private struct MoversCard: View {
    let movers: [LeaderboardView.Mover]
    let movies: [Movie]
    let shows: [Show]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Movers (7 days)").font(.headline)
            if movers.isEmpty {
                Text("No movement yet. Do some comparisons!")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(movers) { m in
                        let resolved: (posterPath: String?, title: String) = {
                            switch m.kind {
                            case .movie:
                                if let mv = movies.first(where: { $0.id == m.id }) {
                                    return (mv.posterPath, mv.title)
                                }
                            case .show:
                                if let sh = shows.first(where: { $0.id == m.id }) {
                                    return (sh.posterPath, sh.title)
                                }
                            }
                            return (nil, "Unknown")
                        }()

                        HStack(spacing: 10) {
                            PosterThumb(posterPath: resolved.posterPath, title: resolved.title, width: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(resolved.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    Image(systemName: m.delta >= 0 ? "arrow.up" : "arrow.down")
                                    Text("\(Int(round(abs(m.delta))))")
                                        .monospacedDigit()
                                }
                                .font(.caption)
                                .foregroundStyle(m.delta >= 0 ? .green : .red)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }
}
