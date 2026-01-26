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
    @State private var isSyncing = false
    @State private var debugLog: String = "Ready."
    
    // FORCE REFRESH HACK
    @State private var refreshID = UUID()
    
    // Alert State
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var profileUserId: String = ""
    
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
                    
                    // 3. DATA INSPECTOR (The Fix)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("🕵️‍♂️ DATA INSPECTOR")
                                .font(.headline).bold()
                                .foregroundStyle(.purple)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Auth: \(userId.prefix(6))...")
                                    .font(.caption.monospaced())
                                    .padding(4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                                if !profileUserId.isEmpty {
                                    Text("Profile: \(profileUserId.prefix(6))...")
                                        .font(.caption.monospaced())
                                        .padding(4)
                                        .background(Color.teal.opacity(0.1))
                                        .cornerRadius(4)
                                }
                            }
                        }
                        
                        Divider()
                        
                        // ACTIONS
                        HStack {
                            Button {
                                injectTestItem()
                            } label: {
                                Text("Force Inject")
                                    .font(.caption).bold()
                                    .padding(8)
                                    .background(Color.orange)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            
                            Button {
                                // Toggle this ID to force SwiftUI to redraw the list
                                refreshID = UUID()
                            } label: {
                                Text("Refresh List")
                                    .font(.caption).bold()
                                    .padding(8)
                                    .background(Color.gray)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            
                            Button {
                                Task { await reassignOrphanedItemsToCurrentUser() }
                            } label: {
                                Text("Reassign Orphans")
                                    .font(.caption).bold()
                                    .padding(8)
                                    .background(Color.purple)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                        
                        Divider()
                        
                        if allUserItems.isEmpty {
                            Text("❌ DATABASE IS EMPTY")
                                .font(.callout).bold().foregroundStyle(.red)
                        } else {
                            Text("Found \(allUserItems.count) items in DB:")
                                .font(.caption).bold()
                            
                            // LIST ITEMS
                            // We attach 'refreshID' to force this loop to update
                            ForEach(allUserItems.prefix(5), id: \.id) { item in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(item.movie?.title ?? "Unknown Title")
                                            .bold()
                                            .lineLimit(1)
                                        Text("Owner: \(item.ownerId.prefix(6))...")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if item.ownerId == userId {
                                        Text("YOURS")
                                            .font(.caption2).bold()
                                            .padding(4)
                                            .background(Color.green.opacity(0.2))
                                            .foregroundColor(.green)
                                            .cornerRadius(4)
                                    } else {
                                        Text("OTHER")
                                            .font(.caption2).bold()
                                            .padding(4)
                                            .background(Color.red.opacity(0.2))
                                            .foregroundColor(.red)
                                            .cornerRadius(4)
                                    }
                                }
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            }
                            .id(refreshID) // <--- THIS FORCES REDRAW
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Log: " + debugLog)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            if !profileUserId.isEmpty && profileUserId.prefix(6) != userId.prefix(6) {
                                Text("⚠️ Auth/Profile ID mismatch. Items may not appear if saved under a different ownerId.")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                    .background(Color.purple.opacity(0.05))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // 4. REST OF UI
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
            .alert("Status", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .refreshable {
                await loadProfile()
            }
            .task {
                await loadSession()
                await loadProfile()
                recalculateBadgesIfNeeded()
            }
            .sheet(isPresented: $showEditProfile) { EditProfileSheet(initialUsername: profile?.username ?? "", initialDisplayName: profile?.fullName ?? "") { newU, newN in Task { try? await SocialService.shared.updateProfile(username: newU, fullName: newN); await loadProfile() } } }
        }
    }
    
    // MARK: - LOGIC
    
    private func injectTestItem() {
        guard userId != "guest", !userId.isEmpty else {
            alertMessage = "Sign in to save items to your profile."
            showAlert = true
            debugLog = "❌ Blocked save: not signed in."
            return
        }
        let testMovie = Movie(
            title: "Test Movie \(Int.random(in: 1...100))",
            year: 2024,
            tmdbID: Int.random(in: 10000...99999),
            posterPath: nil,
            genreIDs: [],
            mediaType: "movie",
            ownerId: userId
        )
        context.insert(testMovie)
        
        let testItem = UserItem(movie: testMovie, state: .seen, ownerId: userId)
        context.insert(testItem)
        
        do {
            try context.save()
            debugLog = "✅ Saved: \(testMovie.title)"
            // Force UI Update
            refreshID = UUID()
        } catch {
            debugLog = "❌ Save Error: \(error.localizedDescription)"
            alertMessage = "Database Error: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    @MainActor
    private func runVerboseSync() async {
        isSyncing = true
        debugLog = "Syncing..."
        
        guard userId != "guest", !userId.isEmpty else {
            debugLog = "❌ Error: Cannot sync as Guest."
            alertMessage = "You must be signed in to sync."
            showAlert = true
            isSyncing = false
            return
        }

        guard let client = AuthService.shared.client else { return }
        
        do {
            let cloudLogs: [CloudLog] = try await client
                .from("logs")
                .select("*")
                .eq("user_id", value: userId)
                .execute()
                .value
            
            debugLog = "Downloaded \(cloudLogs.count) items."
            
            // Process logic here if needed...
            
        } catch {
            debugLog = "Sync Error: \(error.localizedDescription)"
        }
        isSyncing = false
    }
    
    @MainActor
    private func reassignOrphanedItemsToCurrentUser() async {
        guard userId != "guest", !userId.isEmpty else {
            alertMessage = "Sign in to reassign items."
            showAlert = true
            return
        }
        var changed = 0
        for item in allUserItems where item.ownerId != userId {
            item.ownerId = userId
            changed += 1
        }
        do {
            try context.save()
            debugLog = "✅ Reassigned \(changed) items to current user."
            refreshID = UUID()
        } catch {
            debugLog = "❌ Reassign error: \(error.localizedDescription)"
            alertMessage = "Reassign Error: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    private func loadSession() async {
        // Get current user ID from AuthService helper
        userId = AuthService.shared.currentUserId() ?? "guest"
        
        await MainActor.run {
            self.debugLog = userId != "guest" ? "✅ Auth ID: \(userId.prefix(8))..." : "⚠️ Not signed in"
            self.refreshID = UUID()
        }
    }
    private func loadProfile() async {
        do {
            let fetched = try await SocialService.shared.getMyProfile()
            if let p = fetched {
                let profileUuid = p.id.uuidString
                await MainActor.run {
                    self.profile = p
                    self.profileUserId = profileUuid
                    
                    // IMPORTANT: Check if profile ID matches auth ID
                    if profileUuid == self.userId {
                        self.debugLog = "✅ Profile & Auth IDs match"
                    } else {
                        self.debugLog = "⚠️ ID Mismatch! Auth=\(self.userId.prefix(6))... Profile=\(profileUuid.prefix(6))..."
                    }
                    self.refreshID = UUID()
                }
            } else {
                // No profile available
                await MainActor.run {
                    self.profile = nil
                    self.profileUserId = ""
                    self.debugLog = "ℹ️ No profile found. This is normal for new users."
                    self.refreshID = UUID()
                }
            }
        } catch {
            await MainActor.run {
                self.alertMessage = "Profile load error: \(error.localizedDescription)"
                self.showAlert = true
                self.debugLog = "❌ Profile load error: \(error.localizedDescription)"
            }
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
            
            // Sync Tools Link
            NavigationLink(destination: DataRepairView()) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Sync & Migration Tools")
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
        let sourceMovies: [Movie]
        if myItems.isEmpty {
            sourceMovies = myLogs.compactMap { $0.movie }
        } else {
            sourceMovies = myItems.compactMap { $0.movie }
        }
        let relevantMovies = sourceMovies.filter { $0.mediaType == tasteFilter }
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
