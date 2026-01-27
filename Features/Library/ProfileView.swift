import SwiftUI
import SwiftData
import Supabase

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    
    // MARK: - Reactive Data
    // We sort by creation date so new items appear at the TOP
    @Query(sort: \UserItem.createdAt, order: .reverse) private var allUserItems: [UserItem]
    @Query private var allLogs: [LogEntry]
    
    @State private var userId: String = "guest"
    @State private var showEditProfile = false
    @State private var profile: SocialProfile?
    @StateObject private var badgeService = BadgeService.shared
    
    // UI State
    @State private var tasteFilter: String = "movie"
    @State private var showAllTaste = false
    @State private var showBadgeUnlock = false
    
    // Computed Props
    var myItems: [UserItem] { allUserItems.filter { $0.ownerId == userId } }
    var myLogs: [LogEntry] { allLogs.filter { $0.ownerId == userId } }
    
    var statTotalSeen: Int { myItems.filter { $0.state == .seen }.count }
    var statWatchlist: Int { myItems.filter { $0.state == .watchlist }.count }
    
    private var avatarInitial: String {
        String((profile?.displayName ?? "G").prefix(1)).uppercased()
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // 1. HEADER
                    headerSection

                    // 2. STATS
                    statsSection

                    // 3. BADGES
                    badgesSection
                    Divider().padding()
                    tasteProfileSection
                    Divider().padding()
                    settingsSection
                    
                    Spacer(minLength: 50)
                }
            }
            .navigationTitle("Profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .refreshable {
                await loadProfile()
            }
            .task {
                userId = AuthService.shared.currentUserId() ?? "guest"
                await loadProfile()
                recalculateBadgesIfNeeded()
            }
            .sheet(isPresented: $showEditProfile) { EditProfileSheet(initialUsername: profile?.username ?? "", initialDisplayName: profile?.fullName ?? "") { newU, newN in Task { try? await SocialService.shared.updateProfile(username: newU, fullName: newN); await loadProfile() } } }
            .onChange(of: badgeService.latestUnlock) { _, newBadge in
                if newBadge != nil {
                    showBadgeUnlock = true
                }
            }
            .overlay {
                if showBadgeUnlock, let badge = badgeService.latestUnlock {
                    BadgeUnlockOverlay(badge: badge) {
                        showBadgeUnlock = false
                        badgeService.latestUnlock = nil
                    }
                }
            }
        }
    }

    // MARK: - LOGIC

    private func loadProfile() async {
        do {
            let fetched = try await SocialService.shared.getMyProfile()
            await MainActor.run {
                self.profile = fetched
            }
        } catch {
            print("Profile load error: \(error)")
        }
    }
    
    // Components
    var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.1)).frame(width: 100, height: 100)
                Text(avatarInitial).font(.system(size: 40, weight: .heavy)).foregroundStyle(Color.accentColor)
            }
            VStack(spacing: 4) {
                Text(profile?.displayName ?? "Guest").font(.title3).bold()
                if let u = profile?.username { Text("@\(u)").font(.caption).foregroundStyle(.secondary) }
                
                // BUILD VERSION
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    Text("v\(version) (\(build))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            HStack(spacing: 12) {
                if userId != "guest" { Button("Edit Profile") { showEditProfile = true }.font(.caption).bold().padding(.horizontal, 16).padding(.vertical, 8).background(Color.gray.opacity(0.1)).cornerRadius(20) }
                NavigationLink(destination: FriendsView()) { Label("Find Friends", systemImage: "person.badge.plus").font(.caption).bold().padding(.horizontal, 16).padding(.vertical, 8).background(Color.accentColor).foregroundColor(.white).cornerRadius(20) }
            }
        }.padding(.top)
    }
    var statsSection: some View {
        HStack(spacing: 12) {
            StatCard(value: "\(statTotalSeen)", label: "Seen", icon: "checkmark.circle.fill", color: .green)
            StatCard(value: "\(statWatchlist)", label: "Watchlist", icon: "bookmark.fill", color: .blue)
            StatCard(value: "\(myLogs.count)", label: "Logs", icon: "pencil.circle.fill", color: .orange)
        }.padding(.horizontal)
    }
    var badgesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(destination: BadgeGalleryView()) { HStack { Text("Badges").font(.title3).bold().foregroundStyle(.primary); Spacer(); Image(systemName: "chevron.right").font(.caption2).bold().foregroundStyle(.secondary) } }.padding(.horizontal)
            Text("Complete logs to earn badges!").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
        }
    }
    var tasteProfileSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Taste Profile").font(.title3).bold(); Spacer()
                Picker("Type", selection: $tasteFilter) { Image(systemName: "film").tag("movie"); Image(systemName: "tv").tag("tv") }.pickerStyle(.segmented).frame(width: 120)
            }.padding(.horizontal)
            let genreCounts = calculateTaste()
            if genreCounts.isEmpty {
                Text("No data yet.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
            } else {
                let visibleCounts = showAllTaste ? genreCounts : Array(genreCounts.prefix(10))
                ForEach(visibleCounts) { stat in
                    HStack {
                        Text(stat.name).font(.subheadline).fontWeight(.medium)
                        Spacer()
                        Text("\(stat.count)").font(.caption).bold().foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
                if genreCounts.count > 10 {
                    Button(showAllTaste ? "Show Less" : "Show All") {
                        withAnimation { showAllTaste.toggle() }
                    }
                    .font(.caption)
                    .padding(.horizontal)
                }
            }
        }
    }
    var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.headline).padding(.horizontal).padding(.top, 8)

            // Tools & Settings Link (Theme, Import, etc.)
            NavigationLink(destination: SettingsToolsView()) {
                HStack {
                    Image(systemName: "gearshape.fill")
                    Text("Tools & Settings")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .foregroundStyle(.blue)
                .cornerRadius(12)
            }
            .padding(.horizontal)

            // Sync Tools Link
            NavigationLink(destination: DataRepairView()) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Cloud Sync & Recovery")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .foregroundStyle(.orange)
                .cornerRadius(12)
            }
            .padding(.horizontal)

            Button(action: { Task { try? await AuthService.shared.signOut() } }) { HStack { Image(systemName: "rectangle.portrait.and.arrow.right"); Text("Sign Out"); Spacer() }.padding().background(Color.red.opacity(0.1)).foregroundStyle(.red).cornerRadius(12) }.padding(.horizontal)
        }
    }
    struct StatItem: Identifiable { let id = UUID(); let name: String; let count: Int }
    private func calculateTaste() -> [StatItem] {
        var counts: [String: Int] = [:]
        // Use logs as primary source (includes all imported items)
        // Also include items marked as seen
        var allMovies: [Movie] = myLogs.compactMap { $0.movie }
        let seenFromItems = myItems.filter { $0.state == .seen }.compactMap { $0.movie }
        // Combine and deduplicate
        let movieIds = Set(allMovies.map { $0.id })
        for movie in seenFromItems {
            if !movieIds.contains(movie.id) {
                allMovies.append(movie)
            }
        }
        let relevantMovies = allMovies.filter { $0.mediaType == tasteFilter }
        for m in relevantMovies { for g in m.genreIDs { counts[genreIDToString(g), default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }.map { StatItem(name: $0.key, count: $0.value) }
    }
    
    private func recalculateBadgesIfNeeded() {
        guard badgeService.badges.isEmpty else { return }
        let inputs = myLogs.compactMap { log -> BadgeInput? in
            guard let movie = log.movie else { return nil }
            return BadgeInput(watchedOn: log.watchedOn, genreIDs: movie.genreIDs)
        }
        badgeService.calculateBadges(inputs: inputs)
    }
    private func genreIDToString(_ id: Int) -> String { switch id { case 28: return "Action"; case 12: return "Adventure"; case 16: return "Animation"; case 35: return "Comedy"; case 80: return "Crime"; case 99: return "Documentary"; case 18: return "Drama"; case 10751: return "Family"; case 14: return "Fantasy"; case 36: return "History"; case 27: return "Horror"; case 10402: return "Music"; case 9648: return "Mystery"; case 10749: return "Romance"; case 878: return "Sci-Fi"; case 10770: return "TV Movie"; case 53: return "Thriller"; case 10752: return "War"; case 37: return "Western"; default: return "Genre" } }
}

// MARK: - Badge Unlock Overlay
struct BadgeUnlockOverlay: View {
    let badge: AppBadge
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            // Background blur
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 24) {
                Text("Badge Unlocked!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                // Badge icon
                ZStack {
                    Circle()
                        .fill(badge.color.gradient)
                        .frame(width: 120, height: 120)
                        .shadow(color: badge.color.opacity(0.5), radius: 20, x: 0, y: 10)

                    Image(systemName: badge.icon)
                        .font(.system(size: 50, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 8) {
                    Text(badge.name)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)

                    Text(badge.description)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }

                Button {
                    onDismiss()
                } label: {
                    Text("Awesome!")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 200)
                        .padding(.vertical, 14)
                        .background(badge.color)
                        .cornerRadius(25)
                }
                .padding(.top, 8)
            }
            .padding(40)
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}
