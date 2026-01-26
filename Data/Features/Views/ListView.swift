import SwiftUI
import SwiftData

struct ListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Movie.title, order: .forward) private var movies: [Movie]
    @Query private var scores: [Score]

    private func scoreFor(_ m: Movie) -> Int {
        Int((Double(scores.first { $0.movieID == m.id }?.display100 ?? 0)).rounded())
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(movies, id: \.id) { m in
                    HStack(spacing: 12) {
                        PosterThumb(posterPath: m.posterPath, title: m.title, width: 44)

                        VStack(alignment: .leading) {
                            Text(m.title).font(.headline)
                            if let y = m.year { Text("\(y)").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text("\(scoreFor(m))")
                            .font(.headline)
                            .padding(8)
                            .background(Circle().stroke(.secondary))
                    }
                }
            }
            #if os(iOS)
            .listStyle(.inset)
            #endif
            .navigationTitle("Your List")
        }
    }
}

private extension Double {
    var int: Int { Int(self) }
}

