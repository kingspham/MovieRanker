// PodcastInfoView.swift
import SwiftUI
import SwiftData
import SafariServices

struct PodcastInfoView: View {
    @Environment(\.modelContext) private var context
    let item: TMDbItem
    
    @State private var movie: Movie? = nil
    @State private var showLogSheet = false
    @State private var showRankingSheet = false
    @State private var showSuccess = false
    @State private var userId = "guest"
    @State private var showBrowser = false
    @State private var browserURL: URL?
    @State private var prediction: PredictionExplanation?
    @Query private var allScores: [Score]
    @Query private var allUserItems: [UserItem]

    var hasRanked: Bool {
        guard let m = movie else { return false }
        return allScores.contains(where: { $0.movieID == m.id && ($0.ownerId == userId || $0.ownerId == "guest") })
    }

    var myScoreValue: Int? {
        guard let m = movie else { return nil }
        return allScores.first(where: { $0.movieID == m.id && ($0.ownerId == userId || $0.ownerId == "guest") })?.display100
    }

    var isOnWatchlist: Bool {
        guard let m = movie else { return false }
        return allUserItems.contains(where: { $0.movie?.id == m.id && $0.state == .watchlist && ($0.ownerId == userId || $0.ownerId == "guest") })
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    if let path = item.posterPath, let url = URL(string: path) {
                        AsyncImage(url: url) { phase in if let img = phase.image { img.resizable().scaledToFit() } else { Color.gray.opacity(0.2) } }.frame(width: 120).cornerRadius(12).shadow(radius: 5)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.displayTitle).font(.title3).fontWeight(.black)
                        Text("Podcast").font(.caption).bold().padding(6).background(Color.purple.opacity(0.1)).foregroundStyle(.purple).cornerRadius(4)
                        if let tags = item.tags, !tags.isEmpty { Text(tags.prefix(2).joined(separator: " • ")).font(.caption).foregroundStyle(.secondary) }
                    }
                }.padding()
                
                PodcastScoreView(myScoreValue: myScoreValue, prediction: prediction)
                    .padding(.horizontal)
                
                Button { DeepLinkManager.open(providerName: "Spotify", title: item.displayTitle) { url in browserURL = url; showBrowser = true } } label: { HStack { Image(systemName: "headphones"); Text("Listen Now") }.fontWeight(.bold).frame(maxWidth: .infinity).padding().background(Color.black).foregroundColor(.white).cornerRadius(12) }.padding(.horizontal)
                
                HStack {
                    if hasRanked { Button { handleReRank() } label: { Text("Re-Rank").fontWeight(.bold).frame(maxWidth: .infinity).padding().background(Color.orange).foregroundColor(.white).cornerRadius(12) } }
                    else { Button { showLogSheet = true } label: { Text("Mark as Listened").fontWeight(.bold).frame(maxWidth: .infinity).padding().background(Color.accentColor).foregroundColor(.white).cornerRadius(12) } }
                    if isOnWatchlist {
                        Button { removeFromWatchlist() } label: { HStack { Image(systemName: "checkmark"); Text("On List") }.fontWeight(.bold).frame(maxWidth: .infinity).padding().background(Color.green.opacity(0.15)).foregroundColor(.green).cornerRadius(12) }
                    } else {
                        Button { savePodcast(as: .watchlist) } label: { Text("Want to Listen").fontWeight(.bold).frame(maxWidth: .infinity).padding().background(Color.gray.opacity(0.15)).foregroundColor(.primary).cornerRadius(12) }
                    }
                }.padding(.horizontal)
                
                // DESCRIPTION FIX
                if let desc = item.overview, !desc.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About").font(.headline)
                        Text(desc).font(.body).foregroundStyle(.primary).lineSpacing(4)
                    }.padding()
                }
            }
        }
        .navigationTitle("Podcast Details")
        .sheet(isPresented: $showBrowser) {
            if let url = browserURL {
                #if os(iOS)
                SafariView(url: url).ignoresSafeArea()
                #else
                Text("Open \(url.absoluteString) in browser")
                #endif
            }
        }
        .sheet(isPresented: $showLogSheet) { if let m = movie { LogSheet(movie: m, existingLog: nil, showRanking: $showRankingSheet) } }
        .sheet(isPresented: $showRankingSheet) { if let m = movie { RankingSheet(newMovie: m) } }
        .task {
            let actor = AuthService.shared.sessionActor(); if let s = try? await actor.session() { userId = s.userId }
            if movie == nil { await ensurePodcast() }
            if let m = movie {
                let engine = LinearPredictionEngine()
                prediction = engine.predict(for: m, in: context, userId: userId)
            }
        }
        .overlay(alignment: .top) { if showSuccess { SuccessToast(text: "Saved to Library") } }
    }
    
    private func ensurePodcast() async {
        let targetID = item.id
        let allMovies = (try? context.fetch(FetchDescriptor<Movie>())) ?? []
        if let existing = allMovies.first(where: { $0.tmdbID == targetID }) { self.movie = existing }
        else {
            let newPod = Movie(title: item.displayTitle, year: item.year, tmdbID: item.id, posterPath: item.posterPath, tags: item.tags ?? [], mediaType: "podcast", ownerId: userId)
            if let host = item.overview?.replacingOccurrences(of: "Hosted by ", with: "") { newPod.authors = [host] }
            context.insert(newPod); self.movie = newPod
        }
    }
    // (Keep handleReRank / savePodcast)
    private func handleReRank() { guard let m = movie else { return }; if let score = allScores.first(where: { $0.movieID == m.id && ($0.ownerId == userId || $0.ownerId == "guest") }) { context.delete(score); try? context.save() }; showRankingSheet = true }
    private func savePodcast(as state: UserItem.State) { guard let m = movie else { return }; let targetID = m.tmdbID; let allItems = (try? context.fetch(FetchDescriptor<UserItem>())) ?? []; if let existingItem = allItems.first(where: { $0.movie?.tmdbID == targetID }) { existingItem.state = state } else { context.insert(UserItem(movie: m, state: state, ownerId: userId)) }; try? context.save(); showSuccess = true; DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showSuccess = false } }
    private func removeFromWatchlist() { guard let m = movie else { return }; if let existingItem = allUserItems.first(where: { $0.movie?.id == m.id && $0.state == .watchlist && ($0.ownerId == userId || $0.ownerId == "guest") }) { context.delete(existingItem); try? context.save() } }
}

private struct PodcastScoreView: View {
    let myScoreValue: Int?
    let prediction: PredictionExplanation?

    var body: some View {
        VStack(spacing: 12) {
            if let score = myScoreValue {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(Color.blue, lineWidth: 4).frame(width: 50, height: 50)
                        Text("\(score)").font(.headline).fontWeight(.black).foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Score").font(.caption).textCase(.uppercase).foregroundStyle(.secondary)
                        Text("Ranked on Leaderboard").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } else if let pred = prediction {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(Color.purple, lineWidth: 4).frame(width: 50, height: 50)
                        Text("\(Int(pred.score * 10))").font(.headline).fontWeight(.black).foregroundStyle(.purple)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Predicted Score").font(.caption).textCase(.uppercase).foregroundStyle(.secondary)
                        if !pred.reasons.isEmpty {
                            Text(pred.reasons.first ?? "Based on your tastes").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
        }
    }
}
