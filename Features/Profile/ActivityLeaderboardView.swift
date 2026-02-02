// ActivityLeaderboardView.swift
// Shows activity leaderboard to give context to points

import SwiftUI
import SwiftData

struct ActivityLeaderboardView: View {
    @Environment(\.modelContext) private var context
    @Query private var allUserItems: [UserItem]
    @Query private var allLogs: [LogEntry]

    @State private var myUserId: String = "guest"
    @State private var myPoints: Int = 0
    @State private var myRank: Int = 0
    @State private var leaderboard: [LeaderboardEntry] = []
    @State private var isLoading = true

    struct LeaderboardEntry: Identifiable {
        let id: UUID
        let profile: SocialProfile
        let points: Int
        let rank: Int
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading leaderboard...")
            } else {
                List {
                    // My stats section
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your Points")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(formatPoints(myPoints))
                                    .font(.title)
                                    .fontWeight(.bold)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Your Rank")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if myRank > 0 {
                                    Text("#\(myRank)")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.orange)
                                } else {
                                    Text("Unranked")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    } header: {
                        Text("Your Stats")
                    }

                    // Points breakdown
                    Section {
                        HStack {
                            Label("Ranked items", systemImage: "star.fill")
                            Spacer()
                            Text("\(rankedCount) x 100 = \(rankedCount * 100)")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Label("Watchlist items", systemImage: "bookmark.fill")
                            Spacer()
                            Text("\(watchlistCount) x 20 = \(watchlistCount * 20)")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Label("Log entries", systemImage: "pencil.circle.fill")
                            Spacer()
                            Text("\(logCount) x 50 = \(logCount * 50)")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("How Points Work")
                    }

                    // Leaderboard
                    if !leaderboard.isEmpty {
                        Section {
                            ForEach(leaderboard) { entry in
                                ActivityLeaderboardRow(entry: entry, isCurrentUser: entry.id.uuidString == myUserId)
                            }
                        } header: {
                            Text("Top Users")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Activity Leaderboard")
        .task {
            myUserId = AuthService.shared.currentUserId() ?? "guest"
            calculateMyPoints()
            await loadLeaderboard()
            isLoading = false
        }
    }

    private var rankedCount: Int {
        allUserItems.filter { $0.ownerId == myUserId && $0.state == .seen }.count
    }

    private var watchlistCount: Int {
        allUserItems.filter { $0.ownerId == myUserId && $0.state == .watchlist }.count
    }

    private var logCount: Int {
        allLogs.filter { $0.ownerId == myUserId }.count
    }

    private func calculateMyPoints() {
        myPoints = (rankedCount * 100) + (watchlistCount * 20) + (logCount * 50)
    }

    private func loadLeaderboard() async {
        // Get users you follow + yourself to create a friend leaderboard
        let following = await SocialService.shared.fetchFollowing(userId: myUserId)

        // For now, show following users as leaderboard
        // In a full implementation, you'd fetch their activity counts from a server
        var entries: [LeaderboardEntry] = []

        // Add current user to leaderboard
        if let myProfile = try? await SocialService.shared.getMyProfile() {
            entries.append(LeaderboardEntry(
                id: myProfile.id,
                profile: myProfile,
                points: myPoints,
                rank: 0
            ))
        }

        // For following users, we'd need their activity data from the server
        // For now, just show them with estimated points
        for (index, profile) in following.enumerated() {
            entries.append(LeaderboardEntry(
                id: profile.id,
                profile: profile,
                points: 0, // Would need server-side calculation
                rank: 0
            ))
        }

        // Sort by points
        entries.sort { $0.points > $1.points }

        // Assign ranks
        for (index, _) in entries.enumerated() {
            entries[index] = LeaderboardEntry(
                id: entries[index].id,
                profile: entries[index].profile,
                points: entries[index].points,
                rank: index + 1
            )
        }

        // Find my rank
        if let myEntry = entries.first(where: { $0.id.uuidString == myUserId }) {
            myRank = myEntry.rank
        }

        leaderboard = entries
    }

    private func formatPoints(_ points: Int) -> String {
        if points >= 1000000 {
            return String(format: "%.1fM", Double(points) / 1000000.0)
        } else if points >= 1000 {
            return String(format: "%.1fK", Double(points) / 1000.0)
        }
        return "\(points)"
    }
}

struct ActivityLeaderboardRow: View {
    let entry: ActivityLeaderboardView.LeaderboardEntry
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Rank
            Text("#\(entry.rank)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(rankColor)
                .frame(width: 36)

            // Avatar
            Circle()
                .fill(isCurrentUser ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(entry.profile.displayName.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundStyle(isCurrentUser ? .accentColor : .gray)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.profile.displayName)
                        .font(.headline)
                    if isCurrentUser {
                        Text("(You)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let username = entry.profile.username {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Points
            VStack(alignment: .trailing) {
                Text(formatPoints(entry.points))
                    .font(.headline)
                    .fontWeight(.semibold)
                Text("pts")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .background(isCurrentUser ? Color.accentColor.opacity(0.05) : Color.clear)
    }

    private var rankColor: Color {
        switch entry.rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .primary
        }
    }

    private func formatPoints(_ points: Int) -> String {
        if points >= 1000000 {
            return String(format: "%.1fM", Double(points) / 1000000.0)
        } else if points >= 1000 {
            return String(format: "%.1fK", Double(points) / 1000.0)
        }
        return "\(points)"
    }
}
