//
//  MainView.swift
//  MovieRanker
//

import SwiftUI
import SwiftData

struct MainView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            YourListView()
                .tabItem { Label("Your List", systemImage: "list.bullet") }

            LeaderboardView()
                .tabItem { Label("Leaderboard", systemImage: "trophy") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}
