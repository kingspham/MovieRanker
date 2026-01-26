import SwiftUI
import Combine

struct RootTabView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        TabView(selection: $router.selected) {
            // 🔁 Replace FeedView with SearchView
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(AppRouter.Tab.search)

            YourListView()
                .tabItem { Label("Your List", systemImage: "list.bullet") }
                .tag(AppRouter.Tab.list)

            LeaderboardView()
                .tabItem { Label("Leaderboard", systemImage: "trophy") }
                .tag(AppRouter.Tab.leaderboard)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppRouter.Tab.profile)
        }
    }
}
