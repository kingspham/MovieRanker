// FollowListView.swift
// Shows followers or following list

import SwiftUI

enum FollowListMode {
    case followers
    case following
}

struct FollowListView: View {
    let userId: String
    let mode: FollowListMode

    @State private var profiles: [SocialProfile] = []
    @State private var isLoading = true

    var title: String {
        switch mode {
        case .followers: return "Followers"
        case .following: return "Following"
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if profiles.isEmpty {
                ContentUnavailableView(
                    mode == .followers ? "No Followers Yet" : "Not Following Anyone",
                    systemImage: "person.2",
                    description: Text(mode == .followers
                        ? "When people follow you, they'll appear here."
                        : "Find friends to follow and see their activity!")
                )
            } else {
                List(profiles) { profile in
                    NavigationLink(destination: PublicProfileView(profile: profile)) {
                        HStack(spacing: 12) {
                            // Avatar
                            Circle()
                                .fill(Color.accentColor.opacity(0.2))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Text(String(profile.displayName.prefix(1)).uppercased())
                                        .font(.headline)
                                        .foregroundStyle(.accentColor)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName)
                                    .font(.headline)
                                if let username = profile.username {
                                    Text("@\(username)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(title)
        .task {
            await loadProfiles()
        }
        .refreshable {
            await loadProfiles()
        }
    }

    private func loadProfiles() async {
        isLoading = true
        switch mode {
        case .followers:
            profiles = await SocialService.shared.fetchFollowers(userId: userId)
        case .following:
            profiles = await SocialService.shared.fetchFollowing(userId: userId)
        }
        isLoading = false
    }
}
