import SwiftUI

struct FriendSearchView: View {
    @State private var query = ""
    @State private var results: [UserProfile] = []
    @State private var isLoading = false
    @ObservedObject private var friends = FriendsService.shared

    var body: some View {
        VStack {
            HStack {
                TextField("Search username or name", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button("Search") { Task { await runSearch() } }
            }

            if isLoading { ProgressView().padding() }

            List(results) { user in
                HStack {
                    VStack(alignment: .leading) {
                        Text(user.displayName ?? user.username ?? "Unknown")
                        Text(user.id).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if friends.friendIDs.contains(user.id) {
                        Button("Remove") { Task { try? await FriendsService.shared.removeFriend(friendId: user.id) } }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Add") { Task { try? await FriendsService.shared.addFriend(friendId: user.id) } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding()
        .navigationTitle("Find Friends")
        .task { await FriendsService.shared.refresh() }
    }

    private func runSearch() async {
        guard !query.isEmpty else { results = []; return }
        isLoading = true
        defer { isLoading = false }
        do {
            results = try await ProfileService.shared.findUsers(query: query)
        } catch {
            results = []
        }
    }
}
