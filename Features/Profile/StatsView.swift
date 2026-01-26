import SwiftUI
import SwiftData
import Charts // Requires iOS 16+

struct StatsView: View {
    @Environment(\.modelContext) private var context
    @State private var userId: String = "guest"
    
    @Query private var scores: [Score]
    @Query private var movies: [Movie]
    @Query private var userItems: [UserItem]
    
    // FILTERED DATA
    private var myScores: [Score] { scores.filter { $0.ownerId == userId } }
    private var myMovies: [Movie] { movies.filter { $0.ownerId == userId } }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                
                // 1. RATING DISTRIBUTION (The "Grader" Check)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rating Distribution").font(.headline)
                    
                    if myScores.isEmpty {
                        Text("Rate more items to see your distribution.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Chart {
                            ForEach(calculateScoreDistribution(), id: \.range) { bucket in
                                BarMark(
                                    x: .value("Score", bucket.label),
                                    y: .value("Count", bucket.count)
                                )
                                .foregroundStyle(scoreColor(bucket.range.lowerBound))
                                .annotation(position: .top) {
                                    if bucket.count > 0 {
                                        Text("\(bucket.count)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .frame(height: 200)
                        .chartXAxis {
                            AxisMarks(values: .automatic) { _ in
                                AxisValueLabel()
                            }
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(16)
                
                // 2. DECADES (The Time Machine)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Favorite Decades").font(.headline)
                    
                    let decades = calculateDecades()
                    if decades.isEmpty {
                        Text("Log movies with release dates to see this.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Chart {
                            ForEach(decades, id: \.decade) { item in
                                AreaMark(
                                    x: .value("Decade", String(item.decade)),
                                    y: .value("Count", item.count)
                                )
                                .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.6), .blue.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.catmullRom)
                                
                                LineMark(
                                    x: .value("Decade", String(item.decade)),
                                    y: .value("Count", item.count)
                                )
                                .foregroundStyle(.blue)
                                .symbol(.circle)
                            }
                        }
                        .frame(height: 200)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(16)
                
                // 3. MEDIA BREAKDOWN
                VStack(alignment: .leading, spacing: 12) {
                    Text("Media Diet").font(.headline)
                    
                    let types = calculateMediaTypes()
                    if types.isEmpty {
                        Text("No data yet.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 0) {
                            ForEach(types, id: \.type) { item in
                                Rectangle()
                                    .fill(typeColor(item.type))
                                    .frame(height: 30)
                                    .frame(maxWidth: .infinity) // Simple equal width for visual, or weighted:
                                    .overlay(Text(item.type.capitalized).font(.caption2).bold().foregroundColor(.white))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        // Legend
                        VStack(alignment: .leading) {
                            ForEach(types, id: \.type) { item in
                                HStack {
                                    Circle().fill(typeColor(item.type)).frame(width: 8, height: 8)
                                    Text(item.type.capitalized).font(.caption).bold()
                                    Spacer()
                                    Text("\(item.count) items").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(16)
                
            }
            .padding()
        }
        .navigationTitle("Deep Dive")
        .task {
            let actor = AuthService.shared.sessionActor()
            if let s = try? await actor.session() { userId = s.userId }
        }
    }
    
    // MARK: - Logic
    
    struct ScoreBucket { let range: Range<Int>; let label: String; let count: Int }
    
    private func calculateScoreDistribution() -> [ScoreBucket] {
        let buckets = [
            0..<20, 20..<40, 40..<60, 60..<80, 80..<101
        ]
        
        return buckets.map { range in
            let count = myScores.filter { range.contains($0.display100) }.count
            let label = range.upperBound == 101 ? "90-100" : "\(range.lowerBound)-\(range.upperBound - 1)"
            return ScoreBucket(range: range, label: label, count: count)
        }
    }
    
    struct DecadeStat { let decade: Int; let count: Int }
    
    private func calculateDecades() -> [DecadeStat] {
        var counts: [Int: Int] = [:]
        for m in myMovies {
            if let y = m.year {
                let dec = (y / 10) * 10
                counts[dec, default: 0] += 1
            }
        }
        return counts.sorted { $0.key < $1.key }.map { DecadeStat(decade: $0.key, count: $0.value) }
    }
    
    struct TypeStat { let type: String; let count: Int }
    
    private func calculateMediaTypes() -> [TypeStat] {
        var counts: [String: Int] = [:]
        for m in myMovies {
            counts[m.mediaType, default: 0] += 1
        }
        return counts.map { TypeStat(type: $0.key, count: $0.value) }
    }
    
    private func scoreColor(_ start: Int) -> Color {
        if start >= 80 { return .green }
        if start >= 60 { return .blue }
        if start >= 40 { return .orange }
        return .red
    }
    
    private func typeColor(_ type: String) -> Color {
        switch type {
        case "movie": return .orange
        case "tv": return .blue
        case "book": return .green
        case "podcast": return .purple
        default: return .gray
        }
    }
}
