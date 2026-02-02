// NotificationsView.swift
import SwiftUI

struct NotificationsView: View {
    @StateObject private var service = NotificationService.shared
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading notifications...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if service.notifications.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)

                    Text("No Notifications Yet")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("When someone likes or comments on your activity, you'll see it here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Text("Start logging movies and following friends to get activity!")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(service.notifications) { note in
                        NotificationRow(note: note)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Notifications")
        .task {
            await service.forceFetch() // Force fetch to ensure we get latest
            await service.markAllRead()
            isLoading = false
        }
        .refreshable {
            await service.forceFetch()
        }
    }
}

struct NotificationRow: View {
    let note: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Actor Avatar
            Circle()
                .fill(avatarColor)
                .frame(width: 44, height: 44)
                .overlay(
                    Group {
                        if let name = note.actor?.displayName, !name.isEmpty {
                            Text(String(name.prefix(1)).uppercased())
                                .font(.headline)
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.white)
                        }
                    }
                )

            VStack(alignment: .leading, spacing: 4) {
                // Main notification text - using Text concatenation for proper wrapping
                (Text(note.actor?.displayName ?? "Someone")
                    .fontWeight(.semibold) +
                Text(" ") +
                Text(note.message)
                    .foregroundColor(.primary))
                .font(.subheadline)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

                // Timestamp
                Text(note.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Icon based on type
            ZStack {
                Circle()
                    .fill(iconBackgroundColor)
                    .frame(width: 32, height: 32)
                Image(systemName: iconFor(type: note.type))
                    .font(.caption)
                    .foregroundStyle(iconColor)
            }
        }
        .padding(.vertical, 6)
        .opacity(note.read ? 0.7 : 1.0)
    }

    var avatarColor: Color {
        switch note.type {
        case "like": return .red.opacity(0.8)
        case "comment": return .blue.opacity(0.8)
        case "follow": return .green.opacity(0.8)
        default: return .gray.opacity(0.8)
        }
    }

    var iconBackgroundColor: Color {
        switch note.type {
        case "like": return .red.opacity(0.15)
        case "comment": return .blue.opacity(0.15)
        case "follow": return .green.opacity(0.15)
        default: return .gray.opacity(0.15)
        }
    }

    var iconColor: Color {
        switch note.type {
        case "like": return .red
        case "comment": return .blue
        case "follow": return .green
        default: return .gray
        }
    }

    func iconFor(type: String) -> String {
        switch type {
        case "like": return "heart.fill"
        case "comment": return "bubble.left.fill"
        case "follow": return "person.badge.plus"
        default: return "bell.fill"
        }
    }
}
