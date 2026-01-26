import SwiftUI
import SwiftData
import Supabase

struct FeedView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LogEntry.watchedOn, order: .reverse) private var localLogs: [LogEntry]
    @Query private var scores: [Score]
    
    @StateObject private var feedService = FeedService.shared
    @StateObject private var socialService = SocialService.shared
    @StateObject private var notifService = NotificationService.shared
    
    @State private var userId: String = "guest"
    @State private var scope: FeedScope = .following
    @State private var showComments = false
    @State private var selectedLog: CloudLog?
    
    enum FeedScope: String, CaseIterable { case following = "Following"; case global = "Community" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Scope", selection: $scope) { ForEach(FeedScope.allCases, id: \.self) { s in Text(s.rawValue).tag(s) } }.pickerStyle(.segmented).padding()
                    .onChange(of: scope) { _, newScope in Task { await loadData(for: newScope) } }
                
                ScrollView {
                    LazyVStack(spacing: 24) {
                        if feedService.feedItems.isEmpty {
                            ContentUnavailableView(scope == .following ? "No Activity" : "Community Quiet", systemImage: scope == .following ? "person.2.slash" : "globe", description: Text("Log movies or follow friends to see activity.")).padding(.top, 40)
                        } else {
                            ForEach(feedService.feedItems) { item in
                                FeedCard(log: item, currentUserId: userId) { action in handleAction(action, item: item) }
                            }
                        }
                    }.padding(.bottom, 20)
                }
                .refreshable { await loadData(for: scope) }
            }
            .navigationTitle("Activity")
            .sheet(item: $selectedLog) { log in CommentsSheet(log: log) }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: NotificationsView()) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell").font(.title3).foregroundStyle(.primary)
                            if notifService.unreadCount > 0 { Circle().fill(.red).frame(width: 10, height: 10) }
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(destination: ProfileView()) { Image(systemName: "person.crop.circle").font(.title2).foregroundStyle(Color.accentColor) }
                }
            }
            .task {
                let actor = AuthService.shared.sessionActor()
                if let s = try? await actor.session() { userId = s.userId }
                await socialService.loadFollowing()
                await loadData(for: scope)
                await notifService.fetchNotifications()
            }
        }
    }
    
    private func loadData(for currentScope: FeedScope) async {
        if currentScope == .global { await feedService.fetchGlobalFeed() }
        else { await feedService.fetchPersonalizedFeed(myId: userId, friendIDs: socialService.followingIDs) }
    }
    
    private func handleAction(_ action: String, item: CloudLog) {
        if action == "like" { Task { await feedService.toggleLike(log: item); await loadData(for: scope) } }
        else if action == "comment" { selectedLog = item }
    }
}

struct FeedCard: View {
    let log: CloudLog
    let currentUserId: String
    let onAction: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let p = log.profile {
                    NavigationLink(destination: PublicProfileView(profile: p)) {
                        HStack {
                            Circle().fill(Color.gray.opacity(0.2)).frame(width: 36, height: 36).overlay(Text(String((p.displayName).prefix(1))).bold().foregroundStyle(.secondary))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) { Text(p.displayName).font(.subheadline).bold(); Text("rated").font(.caption).foregroundStyle(.secondary); Text(log.title).font(.subheadline).bold().lineLimit(1) }
                                if let d = log.watchedOn { Text(d.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.tertiary) }
                            }
                        }
                    }.buttonStyle(.plain)
                }
                Spacer()
                if let s = log.score { ZStack { Circle().stroke(scoreColor(s), lineWidth: 3).frame(width: 40, height: 40); Text("\(s)").font(.caption).fontWeight(.black).foregroundStyle(scoreColor(s)) } }
            }.padding(.horizontal)
            
            HStack(alignment: .top, spacing: 12) {
                if let path = log.posterPath {
                    if path.contains("http") { AsyncImage(url: URL(string: path)) { p in if let i = p.image { i.resizable().scaledToFill() } else { Color.gray.opacity(0.1) } }.frame(width: 70, height: 105).cornerRadius(8).shadow(radius: 2) }
                    else { PosterThumb(posterPath: path, title: log.title, width: 70).shadow(radius: 2) }
                }
                if let n = log.notes, !n.isEmpty { Text(n).font(.subheadline).lineLimit(4).padding(12).background(Color.gray.opacity(0.05)).cornerRadius(12).frame(maxWidth: .infinity, alignment: .leading) }
            }.padding(.horizontal)
            
            HStack(spacing: 20) {
                Button { onAction("like") } label: { HStack(spacing: 4) { Image(systemName: log.isLiked(by: currentUserId) ? "heart.fill" : "heart").foregroundStyle(log.isLiked(by: currentUserId) ? .red : .secondary); if log.likeCount > 0 { Text("\(log.likeCount)").font(.caption).foregroundStyle(.secondary) } } }.buttonStyle(.plain)
                Button { onAction("comment") } label: { HStack(spacing: 4) { Image(systemName: "bubble.right").foregroundStyle(.secondary); if log.commentCount > 0 { Text("\(log.commentCount)").font(.caption).foregroundStyle(.secondary) } } }.buttonStyle(.plain)
                Spacer()
            }.padding(.horizontal).padding(.bottom, 4)
            Divider().padding(.leading, 16)
        }.padding(.top, 8)
    }
    private func scoreColor(_ score: Int) -> Color { if score >= 90 { return .green }; if score >= 70 { return .blue }; if score >= 50 { return .orange }; return .red }
}

struct CommentsSheet: View {
    let log: CloudLog
    @Environment(\.dismiss) private var dismiss
    @State private var comments: [Comment] = []
    @State private var newComment = ""
    @State private var isPosting = false
    @State private var errorMsg: String?
    
    var body: some View {
        NavigationStack {
            VStack {
                if let err = errorMsg { Text(err).foregroundStyle(.red).font(.caption).padding() }
                
                if comments.isEmpty {
                    ContentUnavailableView("No comments", systemImage: "bubble.left.and.bubble.right", description: Text("Be the first to verify this rating!"))
                    Spacer()
                } else {
                    List(comments) { c in
                        HStack(alignment: .top, spacing: 12) {
                            Text(String((c.profile?.displayName ?? "U").prefix(1))).bold().frame(width: 32, height: 32).background(Color.gray.opacity(0.2), in: Circle())
                            VStack(alignment: .leading) {
                                Text(c.profile?.displayName ?? "User").font(.caption).bold().foregroundStyle(.secondary)
                                Text(c.body).font(.body)
                            }
                        }
                    }
                }
                
                HStack {
                    TextField("Add a comment...", text: $newComment).textFieldStyle(.roundedBorder)
                    Button { postComment() } label: { if isPosting { ProgressView() } else { Text("Post").bold() } }.disabled(newComment.isEmpty || isPosting)
                }.padding()
            }
            .navigationTitle("Comments")
            .task { await loadComments() }
        }
    }
    
    private func postComment() {
        isPosting = true
        errorMsg = nil
        Task {
            do {
                try await FeedService.shared.postComment(log: log, text: newComment)
                newComment = ""
                await loadComments() // Refresh list
            } catch {
                errorMsg = "Failed to post: \(error.localizedDescription)"
            }
            isPosting = false
        }
    }
    
    private func loadComments() async {
        guard let client = AuthService.shared.client else { return }
        do {
            let response: [Comment] = try await client.from("comments").select("*, profiles(*)").eq("log_id", value: log.id).order("created_at", ascending: true).execute().value
            self.comments = response
        } catch { print("Comment load error: \(error)") }
    }
}
