// FeedView.swift
import SwiftUI
import SwiftData
import Supabase

struct FeedView: View {
    @Environment(\.modelContext) private var context
    
    // Local data
    @Query(sort: \LogEntry.watchedOn, order: .reverse) private var localLogs: [LogEntry]
    
    @StateObject private var feedService = FeedService.shared
    @StateObject private var socialService = SocialService.shared
    @StateObject private var notifService = NotificationService.shared
    
    @State private var userId: String = "guest"
    @State private var scope: FeedScope = .following

    // ONBOARDING
    @AppStorage("hasSeenRapidFire") private var hasSeenRapidFire = false
    @State private var showOnboarding = false
    @State private var navigateToRapidFire = false

    // Comments
    @State private var showComments = false
    @State private var selectedLog: CloudLog?

    enum FeedScope: String, CaseIterable {
        case following = "Following"
        case global = "Community"
    }

    // Filter logs by current user before checking count
    var myLogs: [LogEntry] {
        localLogs.filter { $0.ownerId == userId || ($0.ownerId == "guest" && userId == "guest") }
    }

    var isNewUser: Bool { myLogs.count < 5 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Scope", selection: $scope) {
                    ForEach(FeedScope.allCases, id: \.self) { s in Text(s.rawValue).tag(s) }
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: scope) { _, newScope in
                    Task { await loadData(for: newScope) }
                }
                
                ScrollView {
                    LazyVStack(spacing: 24) {
                        if isNewUser {
                            Button { navigateToRapidFire = true } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Build your Profile").font(.headline).foregroundStyle(.primary)
                                        Text("Rate 5 movies to unlock better recommendations.").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "flame.fill").font(.largeTitle).foregroundStyle(.orange)
                                }
                                .padding().background(Color.orange.opacity(0.1)).cornerRadius(12).padding(.horizontal)
                            }
                        }
                        
                        if feedService.feedItems.isEmpty {
                            ContentUnavailableView(scope == .following ? "No Activity" : "Community Quiet", systemImage: scope == .following ? "person.2.slash" : "globe", description: Text(scope == .following ? "Log movies or follow friends to see activity." : "Be the first to post!"))
                                .padding(.top, 40)
                        } else {
                            ForEach(feedService.feedItems) { item in
                                FeedCard(log: item, currentUserId: userId) { action in
                                    handleAction(action, item: item)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
                .refreshable { await loadData(for: scope) }
            }
            .navigationTitle("Activity")
            .sheet(item: $selectedLog, onDismiss: {
                Task { await loadData(for: scope) }
            }) { log in
                CommentsSheet(
                    log: log,
                    onCommentPosted: {
                        Task { await loadData(for: scope) }
                    }
                )
            }
            .sheet(isPresented: $showOnboarding) { OnboardingView(launchRapidFire: $navigateToRapidFire) }
            .navigationDestination(isPresented: $navigateToRapidFire) { RapidFireView() }
            .toolbar {
                // FIX: Use platform-agnostic placement or conditional
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: NotificationsView()) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: notifService.unreadCount > 0 ? "bell.fill" : "bell")
                                .font(.title3)
                                .foregroundStyle(notifService.unreadCount > 0 ? .orange : .primary)
                                .symbolEffect(.bounce, value: notifService.unreadCount)
                            if notifService.unreadCount > 0 {
                                Text("\(min(notifService.unreadCount, 99))")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(Circle().fill(.red))
                                    .offset(x: 8, y: -8)
                            }
                        }
                    }
                }
                #else
                ToolbarItem(placement: .navigation) {
                    NavigationLink(destination: NotificationsView()) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: notifService.unreadCount > 0 ? "bell.fill" : "bell")
                                .font(.title3)
                                .foregroundStyle(notifService.unreadCount > 0 ? .orange : .primary)
                            if notifService.unreadCount > 0 {
                                Text("\(min(notifService.unreadCount, 99))")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(Circle().fill(.red))
                                    .offset(x: 8, y: -8)
                            }
                        }
                    }
                }
                #endif
                
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(destination: ProfileView()) {
                        Image(systemName: "person.crop.circle").font(.title2).foregroundStyle(Color.accentColor)
                    }
                }
            }
            .task {
                let actor = AuthService.shared.sessionActor()
                if let s = try? await actor.session() { userId = s.userId }
                await socialService.loadFollowing()
                await loadData(for: scope)
                await notifService.fetchNotifications()
                
                if !hasSeenRapidFire {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    hasSeenRapidFire = true
                    showOnboarding = true
                }
            }
        }
    }
    
    private func loadData(for currentScope: FeedScope) async {
        if currentScope == .global {
            await feedService.fetchGlobalFeed()
        } else {
            let friendStrings = Array(socialService.followingIDs.map { $0.uuidString })
            await feedService.fetchPersonalizedFeed(myId: userId, friendIDs: friendStrings)
        }
    }
    
    private func handleAction(_ action: String, item: CloudLog) {
        if action == "like" {
            Task {
                await feedService.toggleLike(log: item)
                // Small delay to ensure database write completes before refetch
                try? await Task.sleep(nanoseconds: 300_000_000)
                await loadData(for: scope)
            }
        } else if action == "comment" {
            selectedLog = item
        }
    }
}

// FeedCard & CommentsSheet
struct FeedCard: View {
    let log: CloudLog
    let currentUserId: String
    let onAction: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let p = log.profile {
                    NavigationLink(destination: PublicProfileView(profile: p)) { headerContent(displayName: p.displayName) }.buttonStyle(.plain)
                } else { headerContent(displayName: "User") }
                Spacer()
                if let s = log.score { ZStack { Circle().stroke(scoreColor(s), lineWidth: 3).frame(width: 40, height: 40); Text("\(s)").font(.caption).fontWeight(.black).foregroundStyle(scoreColor(s)) } }
            }.padding(.horizontal)
            HStack(alignment: .top, spacing: 12) {
                // CLICKABLE POSTER - Route to correct view based on media type
                if let path = log.posterPath {
                    let tmdbItem = TMDbItem(
                        id: log.tmdbId ?? 0,
                        title: log.title,
                        posterPath: path,
                        mediaType: log.mediaType
                    )

                    NavigationLink {
                        if log.mediaType == "book" {
                            BookInfoView(item: tmdbItem)
                        } else {
                            MovieInfoView(tmdb: tmdbItem, mediaType: log.mediaType ?? "movie")
                        }
                    } label: {
                        if path.contains("http") {
                            AsyncImage(url: URL(string: path)) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    Color.gray.opacity(0.1)
                                }
                            }
                            .frame(width: 70, height: 105)
                            .cornerRadius(8)
                        } else {
                            PosterThumb(posterPath: path, title: log.title, width: 70)
                        }
                    }
                }
                
                if let n = log.notes, !n.isEmpty {
                    Text(n)
                        .font(.subheadline)
                        .lineLimit(4)
                        .padding(12)
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
            HStack(spacing: 20) {
                Button { onAction("like") } label: { HStack(spacing: 4) { Image(systemName: log.isLiked(by: currentUserId) ? "heart.fill" : "heart").foregroundStyle(log.isLiked(by: currentUserId) ? .red : .secondary); if log.likeCount > 0 { Text("\(log.likeCount)").font(.caption).foregroundStyle(.secondary) } } }.buttonStyle(.plain)
                Button { onAction("comment") } label: { HStack(spacing: 4) { Image(systemName: "bubble.right").foregroundStyle(.secondary); if log.commentCount > 0 { Text("\(log.commentCount)").font(.caption).foregroundStyle(.secondary) } } }.buttonStyle(.plain)
                Spacer()
            }.padding(.horizontal).padding(.bottom, 4)
            Divider().padding(.leading, 16)
        }.padding(.top, 8)
    }
    func headerContent(displayName: String) -> some View {
        let actionWord = log.mediaType == "book" ? "read" : (log.mediaType == "podcast" ? "listened to" : "rated")
        return HStack {
            Circle().fill(Color.gray.opacity(0.2)).frame(width: 36, height: 36).overlay(Text(String(displayName.prefix(1))).bold().foregroundStyle(.secondary))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(displayName).font(.subheadline).bold()
                    Text(actionWord).font(.caption).foregroundStyle(.secondary)
                    Text(log.title).font(.subheadline).bold().lineLimit(1)
                }
                if let d = log.watchedOn {
                    Text(d.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
    private func scoreColor(_ score: Int) -> Color { if score >= 90 { return .green }; if score >= 70 { return .blue }; if score >= 50 { return .orange }; return .red }
}

struct CommentsSheet: View {
    let log: CloudLog
    let onCommentPosted: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var comments: [Comment] = []
    @State private var newComment = ""
    @State private var isSpoiler = false
    @State private var isPosting = false

    var body: some View {
        NavigationStack {
            VStack {
                if comments.isEmpty {
                    ContentUnavailableView("No Comments", systemImage: "bubble.left", description: Text("Be the first to comment!"))
                        .frame(maxHeight: .infinity)
                } else {
                    List(comments) { c in
                        HStack(alignment: .top, spacing: 10) {
                            Text(String((c.profile?.displayName ?? "U").prefix(1)))
                                .bold()
                                .frame(width: 36, height: 36)
                                .background(Color.gray.opacity(0.2), in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(c.profile?.displayName ?? "User")
                                        .font(.subheadline)
                                        .bold()
                                    Text(c.createdAt.formatted(.relative(presentation: .named)))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Text(c.body)
                                    .font(.body)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                }

                Divider()

                HStack(spacing: 12) {
                    TextField("Add comment...", text: $newComment)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isPosting)
                    Button {
                        postComment()
                    } label: {
                        if isPosting {
                            ProgressView()
                                .frame(width: 50)
                        } else {
                            Text("Post")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(newComment.trimmingCharacters(in: .whitespaces).isEmpty || isPosting)
                }
                .padding()
            }
            .navigationTitle("Comments (\(comments.count))")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadComments() }
        }
    }

    private func loadComments() async {
        guard let client = AuthService.shared.client else { return }
        do {
            let response: [Comment] = try await client
                .from("comments")
                .select("*, profiles(*)")
                .eq("log_id", value: log.id)
                .order("created_at", ascending: true)
                .execute()
                .value
            self.comments = response
            print("✅ Loaded \(response.count) comments for log \(log.id)")
        } catch {
            print("❌ Failed to load comments: \(error)")
        }
    }

    private func postComment() {
        guard !newComment.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isPosting = true

        Task {
            do {
                try await FeedService.shared.postComment(log: log, text: newComment, isSpoiler: isSpoiler)
                newComment = ""

                // Wait a moment for database write to complete
                try? await Task.sleep(nanoseconds: 500_000_000)

                // Reload comments to show the new one
                await loadComments()

                // Notify parent to refresh feed
                onCommentPosted?()
            } catch {
                print("❌ Failed to post comment: \(error)")
            }
            isPosting = false
        }
    }
}
