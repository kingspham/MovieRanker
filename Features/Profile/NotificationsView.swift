// NotificationsView.swift
import SwiftUI

struct NotificationsView: View {
    @StateObject private var service = NotificationService.shared
    
    var body: some View {
        List {
            if service.notifications.isEmpty {
                ContentUnavailableView("No Notifications", systemImage: "bell.slash", description: Text("Activity from your friends will show up here."))
            }
            
            ForEach(service.notifications) { note in
                HStack(spacing: 12) {
                    // Actor Avatar
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(Text(String((note.actor?.displayName ?? "U").prefix(1))).bold())
                    
                    VStack(alignment: .leading) {
                        // FIX: Using Markdown interpolation instead of Text + Text
                        Text("**\(note.actor?.displayName ?? "Someone")** \(note.message)")
                            .font(.body)
                        
                        Text(note.createdAt.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    
                    // Icon based on type
                    Image(systemName: iconFor(type: note.type))
                        .foregroundStyle(colorFor(type: note.type))
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Notifications")
        .task {
            await service.fetchNotifications()
            await service.markAllRead()
        }
        .refreshable {
            await service.fetchNotifications()
        }
    }
    
    func iconFor(type: String) -> String {
        if type == "like" { return "heart.fill" }
        if type == "comment" { return "bubble.left.fill" }
        return "person.fill"
    }
    
    func colorFor(type: String) -> Color {
        if type == "like" { return .red }
        if type == "comment" { return .blue }
        return .gray
    }
}
