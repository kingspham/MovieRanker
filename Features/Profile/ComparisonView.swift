import SwiftUI
import SwiftData

struct ComparisonView: View {
    let myName: String
    let theirName: String
    let matchPercent: Int
    
    // Data inputs
    let myMovies: [Movie]
    let myScores: [Score]
    let theirLogs: [CloudLog]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // 1. HEADER GRAPH
                VStack(spacing: 16) {
                    Text("Compatibility")
                        .font(.subheadline).textCase(.uppercase).foregroundStyle(.secondary)
                    
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.1), lineWidth: 15)
                            .frame(width: 150, height: 150)
                        
                        Circle()
                            .trim(from: 0, to: CGFloat(matchPercent) / 100.0)
                            .stroke(
                                LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 15, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 150, height: 150)
                        
                        VStack {
                            Text("\(matchPercent)%")
                                .font(.system(size: 44, weight: .black))
                            Text("Match")
                                .font(.caption).bold().foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top)
                    
                    Text("\(myName) + \(theirName)")
                        .font(.headline)
                }
                
                Divider()
                
                // 2. SHARED LOVES (Both >= 70)
                let loves = getSharedLoves()
                if !loves.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("You Both Love", systemImage: "heart.fill")
                            .font(.title3).bold().foregroundStyle(.green)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(loves) { item in
                                    VStack {
                                        if let path = item.log.posterPath {
                                            PosterImage(path: path)
                                        }
                                        HStack(spacing: 4) {
                                            Text("\(item.myScore)").font(.caption).bold().foregroundStyle(.blue)
                                            Text("/").font(.caption2).foregroundStyle(.secondary)
                                            Text("\(item.theirScore)").font(.caption).bold().foregroundStyle(.purple)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                // 3. BIGGEST DISAGREEMENTS (Diff > 30)
                let fights = getDisagreements()
                if !fights.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("The Battleground", systemImage: "bolt.fill")
                            .font(.title3).bold().foregroundStyle(.orange)
                            .padding(.horizontal)
                        
                        ForEach(fights) { item in
                            HStack(spacing: 12) {
                                if let path = item.log.posterPath {
                                    PosterImage(path: path, width: 50, height: 75)
                                }
                                VStack(alignment: .leading) {
                                    Text(item.log.title).font(.headline)
                                    HStack {
                                        Text("You: \(item.myScore)").foregroundStyle(scoreColor(item.myScore))
                                        Text("vs")
                                        Text("Them: \(item.theirScore)").foregroundStyle(scoreColor(item.theirScore))
                                    }
                                    .font(.subheadline).bold()
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                // 4. GENRE BREAKDOWN
                VStack(alignment: .leading, spacing: 16) {
                    Label("Genre Vibe", systemImage: "chart.bar.fill")
                        .font(.title3).bold().padding(.horizontal)
                    
                    let comparison = getGenreComparison()
                    ForEach(comparison, id: \.genre) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.genre).font(.caption).bold().foregroundStyle(.secondary)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    // Background
                                    Capsule().fill(Color.gray.opacity(0.1))
                                    
                                    // My Bar (Blue)
                                    Capsule().fill(Color.blue.opacity(0.8))
                                        .frame(width: geo.size.width * row.myPct)
                                    
                                    // Their Bar (Purple) - overlaid with blend or offset?
                                    // Let's do side-by-side thin lines for clarity
                                }
                            }
                            .frame(height: 8)
                            
                            // Custom split bar visual
                            HStack(spacing: 2) {
                                Capsule().fill(Color.blue).frame(height: 6)
                                    .frame(width: max(0, CGFloat(row.myPct) * 200))
                                Spacer()
                                Capsule().fill(Color.purple).frame(height: 6)
                                    .frame(width: max(0, CGFloat(row.theirPct) * 200))
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    HStack {
                        Circle().fill(Color.blue).frame(width: 8, height: 8)
                        Text("You").font(.caption)
                        Circle().fill(Color.purple).frame(width: 8, height: 8)
                        Text("Them").font(.caption)
                    }
                    .padding(.horizontal)
                }
                
                Spacer(minLength: 50)
            }
            .padding(.vertical)
        }
        .navigationTitle("Taste Check")
    }
    
    // MARK: - Subviews
    
    func PosterImage(path: String, width: CGFloat = 80, height: CGFloat = 120) -> some View {
        AsyncImage(url: URL(string: path.contains("http") ? path : "https://image.tmdb.org/t/p/w185\(path)")) { p in
            if let i = p.image { i.resizable().scaledToFill() } else { Color.gray.opacity(0.2) }
        }
        .frame(width: width, height: height).cornerRadius(8).shadow(radius: 2)
    }
    
    private func scoreColor(_ s: Int) -> Color {
        s >= 70 ? .green : (s >= 40 ? .orange : .red)
    }
    
    // MARK: - Logic
    
    struct ComparisonItem: Identifiable {
        let id = UUID()
        let log: CloudLog
        let myScore: Int
        let theirScore: Int
    }
    
    private func getSharedLoves() -> [ComparisonItem] {
        var items: [ComparisonItem] = []
        for log in theirLogs {
            // Find my score for this movie
            if let tmdb = log.tmdbId,
               let myMov = myMovies.first(where: { $0.tmdbID == tmdb }),
               let myScore = myScores.first(where: { $0.movieID == myMov.id })?.display100,
               let theirScore = log.score {
                
                // Both > 70
                if myScore >= 70 && theirScore >= 70 {
                    items.append(ComparisonItem(log: log, myScore: myScore, theirScore: theirScore))
                }
            }
        }
        return items.sorted { ($0.myScore + $0.theirScore) > ($1.myScore + $1.theirScore) }
    }
    
    private func getDisagreements() -> [ComparisonItem] {
        var items: [ComparisonItem] = []
        for log in theirLogs {
            if let tmdb = log.tmdbId,
               let myMov = myMovies.first(where: { $0.tmdbID == tmdb }),
               let myScore = myScores.first(where: { $0.movieID == myMov.id })?.display100,
               let theirScore = log.score {
                
                // Diff > 30
                if abs(myScore - theirScore) >= 30 {
                    items.append(ComparisonItem(log: log, myScore: myScore, theirScore: theirScore))
                }
            }
        }
        return items.sorted { abs($0.myScore - $0.theirScore) > abs($1.myScore - $1.theirScore) }
    }
    
    struct GenreStat { let genre: String; let myPct: Double; let theirPct: Double }
    
    private func getGenreComparison() -> [GenreStat] {
        var myCounts: [String: Int] = [:]
        var theirCounts: [String: Int] = [:]
        
        // Mine
        for m in myMovies {
            let tags = (m.mediaType == "book" || m.mediaType == "podcast") ? m.tags : m.genreIDs.map(genreIDToString)
            for t in tags { myCounts[t, default: 0] += 1 }
        }
        
        // Theirs
        for log in theirLogs {
            if let tags = log.genres {
                for t in tags { theirCounts[t, default: 0] += 1 }
            }
        }
        
        let myTotal = Double(max(1, myCounts.values.reduce(0, +)))
        let theirTotal = Double(max(1, theirCounts.values.reduce(0, +)))
        
        let allGenres = Set(myCounts.keys).union(theirCounts.keys)
        var stats: [GenreStat] = []
        
        for g in allGenres {
            let myPct = Double(myCounts[g] ?? 0) / myTotal
            let theirPct = Double(theirCounts[g] ?? 0) / theirTotal
            // Only include relevant ones
            if myPct > 0.05 || theirPct > 0.05 {
                stats.append(GenreStat(genre: g, myPct: myPct, theirPct: theirPct))
            }
        }
        
        return stats.sorted { $0.myPct > $1.myPct }.prefix(6).map { $0 }
    }
    
    private func genreIDToString(_ id: Int) -> String {
        switch id {
        case 28: return "Action"; case 12: return "Adventure"; case 16: return "Animation"; case 35: return "Comedy"; case 80: return "Crime"; case 99: return "Documentary"; case 18: return "Drama"; case 10751: return "Family"; case 14: return "Fantasy"; case 36: return "History"; case 27: return "Horror"; case 10402: return "Music"; case 9648: return "Mystery"; case 10749: return "Romance"; case 878: return "Sci-Fi"; case 10770: return "TV Movie"; case 53: return "Thriller"; case 10752: return "War"; case 37: return "Western"; default: return "Genre"
        }
    }
}
