//
//  CompareShowsView.swift
//  MovieRanker
//

import SwiftUI
import SwiftData

/// Compare two *seen* shows and update Scores via Elo.
/// Records snapshots for Top Movers.
struct CompareShowsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let seed: Show?

    @State private var candidates: [Show] = []
    @State private var currentPair: (Show, Show)?
    @State private var round: Int = 1
    @State private var deltas: [Delta] = []

    private let roundsPerSession = 7
    private var userId: String { SessionManager.shared.userId ?? "guest" }
    @State private var recentPairs: Set<PairKey> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Which did you prefer?").font(.headline)
                HStack {
                    Text("Round \(round) of \(roundsPerSession)")
                    Spacer()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let (a, b) = currentPair {
                    choiceButton(for: a) { pick(a, over: b) }
                    Text("vs").foregroundStyle(.secondary)
                    choiceButton(for: b) { pick(b, over: a) }
                } else {
                    ContentUnavailableView(
                        "Not enough watched shows",
                        systemImage: "checkmark.circle",
                        description: Text("Mark more shows as watched to start ranking.")
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

    private func choiceButton(for show: Show, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                PosterThumb(posterPath: show.posterPath, title: show.title, width: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(show.title).font(.headline)
                    if let y = show.yearStart {
                        Text(String(y)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(Int(scoreFor(show).display100))")
                    .font(.headline).monospacedDigit().foregroundStyle(.secondary)
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
        var seen: [Show] = items.compactMap { $0.state == .seen ? $0.show : nil }
        if let s = seed, !seen.contains(where: { $0.id == s.id }) { seen.append(s) }
        guard seen.count >= 2 else { currentPair = nil; return }
        candidates = seen
        ensureScores(for: candidates)
        currentPair = nextPair()
    }

    private func nextPair() -> (Show, Show)? {
        guard candidates.count >= 2 else { return nil }
        let allScores: [Score] = context.fetchAll(Score.self)
        let scores: [UUID: Score] = allScores.reduce(into: [:]) { map, s in if let id = s.movieID { map[id] = s } }

        var best: (Show, Show)?
        var bestDelta = Double.greatestFiniteMagnitude
        let attempts = min(200, candidates.count * candidates.count)

        for _ in 0..<attempts {
            let a = candidates.randomElement()!
            var b = candidates.randomElement()!
            var guardCount = 0
            while b.id == a.id && guardCount < 10 { b = candidates.randomElement()!; guardCount += 1 }

            let key = PairKey(a.id, b.id)
            if recentPairs.contains(key) { continue }

            let sa = scores[a.id]?.display100 ?? 50
            let sb = scores[b.id]?.display100 ?? 50
            let d = abs(sa - sb)
            if d < bestDelta { bestDelta = d; best = (a, b) }
        }

        if let pair = best {
            recentPairs.insert(PairKey(pair.0.id, pair.1.id))
            return pair
        }
        let a = candidates[0]
        let bIndex = candidates.firstIndex(where: { $0.id != a.id }) ?? 1
        let b = candidates[bIndex]
        recentPairs.insert(PairKey(a.id, b.id))
        return (a, b)
    }

    private func pick(_ winner: Show, over loser: Show) {
        var scores: [Score] = context.fetchAll()
        let owner = userId

        func score(for show: Show) -> Score {
            if let s = scores.first(where: { $0.movieID == show.id }) { return s }
            let s = Score(movieID: show.id, display100: 50, latent: 0, variance: 1, ownerId: owner)
            context.insert(s); scores.append(s); return s
        }

        let sW = score(for: winner)
        let sL = score(for: loser)
        let beforeW = sW.display100
        let beforeL = sL.display100

        let (uW, uL) = SimpleElo.update(displayWinner: sW.display100, displayLoser: sL.display100, K: 28)
        sW.display100 = uW
        sL.display100 = uL

        deltas.append(.init(title: winner.title, delta: uW - beforeW))
        deltas.append(.init(title: loser.title,  delta: uL - beforeL))

        SnapshotService.recordShow(winner, score: uW, ownerId: owner, context: context)
        SnapshotService.recordShow(loser,  score: uL, ownerId: owner, context: context)

        SD.save(context)

        round += 1
        if round > roundsPerSession { return }
        currentPair = nextPair()
    }

    // MARK: - Scores

    private func ensureScores(for shows: [Show]) {
        let owner = userId
        let scores: [Score] = context.fetchAll()
        for s in shows where scores.first(where: { $0.movieID == s.id }) == nil {
            context.insert(Score(movieID: s.id, display100: 50, latent: 0, variance: 1, ownerId: owner))
        }
        SD.save(context)
    }

    private func scoreFor(_ s: Show) -> Score {
        let scores: [Score] = context.fetchAll()
        return scores.first(where: { $0.movieID == s.id }) ??
            Score(movieID: s.id, display100: 50, latent: 0, variance: 1, ownerId: userId)
    }

    // MARK: - Types

    private struct PairKey: Hashable {
        let a: UUID
        let b: UUID

        init(_ a: UUID, _ b: UUID) {
            let ordered = PairKey.order(a, b)
            self.a = ordered.0
            self.b = ordered.1
        }

        private static func order(_ x: UUID, _ y: UUID) -> (UUID, UUID) {
            // Compare by uuidString to create a stable ordering without any optional binding
            return x.uuidString < y.uuidString ? (x, y) : (y, x)
        }
    }

    private struct Delta: Identifiable {
        let id = UUID()
        let title: String
        let delta: Double
    }
}

// MARK: - Minimal Elo

private enum SimpleElo {
    static func update(displayWinner w: Double, displayLoser l: Double, K: Double) -> (Double, Double) {
        func toElo(_ d: Double) -> Double { 1000 + d * 10 }
        func toDisp(_ e: Double) -> Double { max(0, min(100, (e - 1000) / 10)) }
        let rW = toElo(w), rL = toElo(l)
        let eW = 1 / (1 + pow(10, (rL - rW)/400))
        let rW2 = rW + K * (1 - eW)
        let rL2 = rL + K * (0 - (1 - eW))
        return (toDisp(rW2), toDisp(rL2))
    }
}

