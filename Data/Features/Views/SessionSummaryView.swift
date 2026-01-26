import SwiftUI

/// Shown at the end of a ranking session. Displays the biggest movers in this session.
struct SessionSummaryView: View {
    struct Delta: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let delta: Double
    }

    /// All per-comparison deltas collected during the session.
    let deltas: [Delta]

    /// Called when the user taps "Rank More".
    var onRankMore: () -> Void = {}

    /// Called when the user taps "Done".
    var onClose: () -> Void = {}

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {

                if movers.risers.isEmpty && movers.droppers.isEmpty {
                    ContentUnavailableView(
                        "No changes",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Do a few comparisons to see rank movements.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    List {
                        if !movers.risers.isEmpty {
                            Section("Biggest Risers") {
                                ForEach(movers.risers) { d in
                                    row(title: d.title, valueText: "+\(format(d.delta))", color: .green)
                                }
                            }
                        }
                        if !movers.droppers.isEmpty {
                            Section("Biggest Droppers") {
                                ForEach(movers.droppers) { d in
                                    row(title: d.title, valueText: "-\(format(-d.delta))", color: .red)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .padding(.top)
            .navigationTitle("Session Summary")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onClose() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rank More") { onRankMore() }
                }
            }
        }
    }

    // MARK: - Rows

    private func row(title: String, valueText: String, color: Color) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(valueText)
                .foregroundStyle(color)
                .monospacedDigit()
                .font(.headline)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Movers (top 5 up & down)

    /// Collapses multiple deltas per title, sums them, and returns top movers.
    private var movers: (risers: [Delta], droppers: [Delta]) {
        let summed: [String: Double] = deltas.reduce(into: [:]) { acc, d in
            acc[d.title, default: 0] += d.delta
        }
        let rows: [Delta] = summed.map { .init(title: $0.key, delta: $0.value) }

        let ups = rows
            .filter { $0.delta > 0 }
            .sorted { $0.delta > $1.delta }
            .prefix(5)

        let downs = rows
            .filter { $0.delta < 0 }
            .sorted { $0.delta < $1.delta }
            .prefix(5)

        return (Array(ups), Array(downs))
    }

    private func format(_ d: Double) -> String {
        "\(Int(round(d)))"
    }
}
