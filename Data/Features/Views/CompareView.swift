import SwiftUI
import SwiftUI
import SwiftData

/// Compare two *seen* movies and update Scores via Elo.
/// Smarter pairing + session summary, and snapshot recording for weekly "Top Movers".
struct CompareView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let seed: Movie?

    @State private var candidates: [Movie] = []
    @State private var currentPair: (Movie, Movie)?
    @State private var round: Int = 1
    @State private var deltas: [Delta] = []

    private let roundsPerSession = 7
    private var userId: String { SessionManager.shared.userId ?? "guest" }
    @State private var recentPairs: Set<PairKey> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Which did you prefer?").font(.headline)

                HStack { Text("Round \(round) of \(roundsPerSession)"); Spacer() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let pair = currentPair {
                    let a = pair.0, b = pair.1
                    choiceButton(for: a) { pick(a, over: b) }
                    Text("vs").foregroundStyle(.secondary)
                    choiceButton(for: b) { pick(b, over: a) }
                } else {
                    ContentUnavailableView(
                        "Not enough watched movies",
                        systemImage: "checkmark.circle",
                        description: Text("Mark more movies as watched to start ranking.")
                    )
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Ranking")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await prepare() }
            .sheet(isPresented: Binding(get: { round > roundsPerSession && !deltas.isEmpty },
                                        set: { _ in })) {
                SessionSummaryView(
                    deltas: deltas.map { .init(title: $0.title, delta: $0.delta) },
                    onClose: { dismiss() }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - UI

    private func choiceButton(for movie: Movie, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                PosterThumb(posterPath: movie.posterPath, title: movie.title, width: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(movie.title).font(.headline)
                    if let y = movie.year { Text(String(y)).foregroundStyle(.secondary) }
                }
                Spacer()
                Text("\(scoreFor(movie).display100)")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(radius: 1, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Flow

    @MainActor
    private func prepare() async {
        let items: [UserItem] = context.fetchAll()
        var seen: [Movie] = items.compactMap { $0.state == .seen ? $0.movie : nil }
        if let s = seed, seen.contains(where: { $0.id == s.id }) == false { seen.append(s) }
        guard seen.count >= 2 else { currentPair = nil; return }
        candidates = seen
        ensureScores(for: candidates)
        currentPair = nextPair()
    }

    private func nextPair() -> (Movie, Movie)? {
        guard candidates.count >= 2 else { return nil }

        let scoresById: [UUID: Score] = context.fetchAll().reduce(into: [:]) { dict, score in
            dict[score.movieID] = score
        }

        var best: (Movie, Movie)?
        var bestDelta: Int = .max
        let attempts = min(200, candidates.count * candidates.count)

        for _ in 0..<attempts {
            guard let a = candidates.randomElement() else { continue }
            var b = candidates.randomElement()
            var guardCount = 0
            while (b?.id == a.id) && guardCount < 10 {
                b = candidates.randomElement(); guardCount += 1
            }
            guard let b else { continue }

            let key = PairKey(a.id, b.id)
            if recentPairs.contains(key) { continue }

            let sa = scoresById[a.id]?.display100 ?? 50
            let sb = scoresById[b.id]?.display100 ?? 50
            let d = abs(sa - sb)
            if d < bestDelta { bestDelta = d; best = (a, b) }
        }

        if let pair = best {
            recentPairs.insert(PairKey(pair.0.id, pair.1.id))
            return pair
        }
        let a = candidates[0]
        let b = candidates.first(where: { $0.id != a.id })!
        recentPairs.insert(PairKey(a.id, b.id))
        return (a, b)
    }

    private func pick(_ winner: Movie, over loser: Movie) {
        var scores: [Score] = context.fetchAll()
        let owner = userId

        func score(for movie: Movie) -> Score {
            if let s = scores.first(where: { $0.movieID == movie.id }) { return s }
            let s = Score(movieID: movie.id, display100: 50, latent: 0, variance: 1, ownerId: owner)
            context.insert(s); scores.append(s); return s
        }

        let sW = score(for: winner)
        let sL = score(for: loser)
        let beforeW = sW.display100
        let beforeL = sL.display100

        let (uW, uL) = SimpleElo.update(displayWinner: sW.display100, displayLoser: sL.display100, K: 28)

        deltas.append(.init(title: winner.title, delta: Double(uW) - Double(beforeW)))
        deltas.append(.init(title: loser.title,  delta: Double(uL) - Double(beforeL)))

        SnapshotService.recordMovie(winner, score: Double(uW), ownerId: owner, context: context)
        SnapshotService.recordMovie(loser,  score: Double(uL), ownerId: owner, context: context)

        SD.save(context)

        round += 1
        guard round <= roundsPerSession else { return }
        currentPair = nextPair()
    }

    // MARK: - Scores

    private func ensureScores(for movies: [Movie]) {
        let owner = userId
        let scores: [Score] = context.fetchAll()
        for m in movies where scores.first(where: { $0.movieID == m.id }) == nil {
            context.insert(Score(movieID: m.id, display100: 50, latent: 0, variance: 1, ownerId: owner))
        }
        SD.save(context)
    }

    private func scoreFor(_ m: Movie) -> Score {
        let scores: [Score] = context.fetchAll()
        if let s = scores.first(where: { $0.movieID == m.id }) { return s }
        let s = Score(movieID: m.id, display100: 50, latent: 0, variance: 1, ownerId: userId)
        context.insert(s)
        return s
    }

    // MARK: - Types

    private struct PairKey: Hashable {
        let a: UUID; let b: UUID
        init(_ a: UUID, _ b: UUID) {
            if a.uuidString < b.uuidString { self.a = a; self.b = b }
            else { self.a = b; self.b = a }
        }
    }

    private struct Delta: Identifiable {
        let id = UUID()
        let title: String
        let delta: Double
    }
}

// Minimal Elo in display-space 0–100
private enum SimpleElo {
    static func update(displayWinner w: Int, displayLoser l: Int, K: Double) -> (Int, Int) {
        func toElo(_ d: Int) -> Double { 1000 + Double(d) * 10 }
        func toDisp(_ e: Double) -> Int { Int(max(0, min(100, round((e - 1000) / 10)))) }
        let rW = toElo(w), rL = toElo(l)
        let eW = 1 / (1 + pow(10, (rL - rW)/400))
        let rW2 = rW + K * (1 - eW)
        let rL2 = rL + K * (0 - (1 - eW))
        return (toDisp(rW2), toDisp(rL2))
    }
}
