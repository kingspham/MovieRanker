import SwiftUI
import SwiftData

struct PublicProfileView: View {
    let profile: SocialProfile
    
    @Environment(\.modelContext) private var context
    @State private var items: [PublicLog] = []
    @State private var stats: PublicStats?
    @State private var isLoading = true
    @State private var isFollowing = false
    
    // Viewership Intersection
    @State private var sharedCount: Int = 0
    @State private var theirTotal: Int = 0
    
    @State private var myId: String = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Circle().fill(Color.gray.opacity(0.2)).frame(width: 100, height: 100)
                        .overlay(Text(String(profile.displayName.prefix(1)).uppercased()).font(.largeTitle).bold())
                    
                    Text(profile.displayName).font(.title2).bold()
                    Text("@\(profile.username ?? "user")").foregroundStyle(.secondary)

                    // Don't show follow button for yourself
                    if profile.id.uuidString != myId {
                        Button(isFollowing ? "Following" : "Follow") {
                            Task { await toggleFollow() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isFollowing ? .gray : .blue)
                    }
                }
                .padding(.top)
                
                // COMPARE STATS
                if !isLoading {
                    HStack(spacing: 40) {
                        VStack {
                            Text("\(stats?.totalLogs ?? 0)").font(.headline)
                            Text("Logged").font(.caption).foregroundStyle(.secondary)
                        }
                        VStack {
                            Text("\(sharedCount)/\(theirTotal)").font(.headline)
                            Text("You've Seen").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(12)
                }
                
                // Recent Activity
                VStack(alignment: .leading) {
                    Text("Recent Activity").font(.headline).padding(.horizontal)
                    
                    if items.isEmpty {
                        ContentUnavailableView("No activity", systemImage: "clock")
                    } else {
                        ForEach(items) { item in
                            HStack {
                                if let url = item.posterURL {
                                    AsyncImage(url: url) { $0.image?.resizable().scaledToFill() }
                                        .frame(width: 50, height: 75).cornerRadius(8)
                                } else {
                                    Rectangle().fill(Color.gray.opacity(0.3))
                                        .frame(width: 50, height: 75).cornerRadius(8)
                                }
                                VStack(alignment: .leading) {
                                    Text(item.title).bold()
                                    if let s = item.score { Text("Score: \(s)").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .navigationTitle(profile.username ?? "Profile")
        .task {
            await loadPublicData()
            await checkFollowStatus()
        }
    }
    
    private func loadPublicData() async {
        // 1. Fetch Cloud Data (Async, Background)
        // Note: Using uuidString because SocialProfile.id is UUID
        let fetchedItems = await FeedService.shared.fetchUserLogs(userId: profile.id.uuidString)
        
        // 2. Fetch Session (Async, Background)
        let session = try? await AuthService.shared.sessionActor().session()
        let currentUserId = session?.userId ?? ""
        
        // 3. Update UI & Calculate Local Stats (Main Thread)
        await MainActor.run {
            self.items = fetchedItems
            self.myId = currentUserId
            
            // Get My Movies to compare
            let allMovies = (try? context.fetch(FetchDescriptor<Movie>())) ?? []
            let myMovies = allMovies.filter { $0.ownerId == currentUserId }
            let myIDs = Set(myMovies.compactMap { $0.tmdbID })
            
            let theirIDs = Set(fetchedItems.map { $0.tmdbID })
            
            self.theirTotal = theirIDs.count
            self.sharedCount = theirIDs.intersection(myIDs).count
            self.stats = PublicStats(totalLogs: fetchedItems.count)
            self.isLoading = false
        }
    }
    
    private func checkFollowStatus() async {
        // SocialService takes String ID
        let following = await SocialService.shared.fetchFollowing(userId: myId)
        isFollowing = following.contains { $0.id == profile.id }
    }
    
    private func toggleFollow() async {
        // SocialService takes String ID
        let targetId = profile.id.uuidString
        
        if isFollowing {
            try? await SocialService.shared.unfollow(targetId: targetId)
        } else {
            try? await SocialService.shared.follow(targetId: targetId)
        }
        isFollowing.toggle()
    }
}

struct PublicStats {
    let totalLogs: Int
}

struct PublicLog: Identifiable {
    let id: UUID
    let title: String
    let posterPath: String?
    let score: Int?
    let tmdbID: Int
    
    var posterURL: URL? {
        TMDbClient.makeImageURL(path: posterPath ?? "", size: .w185)
    }
}
