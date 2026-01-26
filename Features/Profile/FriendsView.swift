import SwiftUI

struct FriendsView: View {
    @StateObject private var service = SocialService.shared
    @State private var query = ""
    @State private var results: [SocialProfile] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if results.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                
                ForEach(results) { user in
                    FriendRow(user: user, service: service)
                }
            }
            .searchable(text: $query, prompt: "Find friends by username...")
            .navigationTitle("Find Friends")
            .onChange(of: query) { _, _ in Task { await performSearch() } }
            .task { await service.loadFollowing() }
        }
    }
    
    private func performSearch() async {
        guard !query.isEmpty else { results = []; return }
        try? await Task.sleep(nanoseconds: 300_000_000) // Debounce
        isLoading = true
        do { results = try await service.searchUsers(query: query) } catch { print(error) }
        isLoading = false
    }
}

// MARK: - Subview (Fixes Compiler Complexity Error)
struct FriendRow: View {
    let user: SocialProfile
    @ObservedObject var service: SocialService
    
    var body: some View {
        HStack {
            // CLICKABLE PROFILE PART
            NavigationLink(destination: PublicProfileView(profile: user)) {
                HStack {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(Text(String(user.displayName.prefix(1))).bold())
                    
                    VStack(alignment: .leading) {
                        Text(user.username ?? "User").font(.headline)
                        if let name = user.fullName {
                            Text(name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer() // Push button to edge
                }
            }
            // Make the row content transparent so the button below works
            .buttonStyle(.plain)
            
            // FOLLOW BUTTON (Separate from link)
            // SocialService.followingIDs is Set<UUID>, user.id is UUID. This works.
            let isFollowing = service.followingIDs.contains(user.id)
            
            Button {
                Task {
                    // Convert UUID to String for the Service methods
                    let idString = user.id.uuidString
                    if isFollowing {
                        try? await service.unfollow(targetId: idString)
                    } else {
                        try? await service.follow(targetId: idString)
                    }
                }
            } label: {
                Text(isFollowing ? "Following" : "Follow")
                    .font(.caption).bold()
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(isFollowing ? Color.gray.opacity(0.2) : Color.accentColor)
                    .foregroundColor(isFollowing ? .primary : .white)
                    .cornerRadius(16)
            }
            .buttonStyle(.plain) // Crucial: Prevents tapping row from triggering button
        }
    }
}
