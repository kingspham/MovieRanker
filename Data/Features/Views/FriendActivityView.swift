import SwiftUI

struct FriendActivityView: View {
    @ObservedObject private var friends = FriendsService.shared
    @State private var items: [FriendActivityItem] = []
    @State private var isLoading = false

    var body: some View {
        List {
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() } }
            ForEach(items) { it in
                VStack(alignment: .leading, spacing: 6) {
                    Text(it.movieTitle).font(.headline)
                    Text(it.body).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text(it.createdAt, format: .relative(presentation: .named))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        // placeholder for author display once profiles are richer
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Friend Activity")
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        isLoading = true; defer { isLoading = false }
        await FriendsService.shared.refresh()
        items = await FriendActivityService.shared.fetchRecentReviews(friendIDs: friends.friendIDs)
    }
}
