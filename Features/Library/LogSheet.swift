import SwiftUI
import SwiftData

struct LogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    
    let movie: Movie
    let existingLog: LogEntry?
    @Binding var showRanking: Bool
    
    @State private var watchedOn = Date()
    @State private var unknownDate = false
    @State private var notes = ""
    @State private var platform: String = "Theater"
    @State private var withWho: String = ""
    @State private var userId: String = "guest"
    @State private var selectedBookFormat: BookFormat = .physical

    // Social tagging
    @State private var showFriendPicker = false
    @State private var taggedUsers: [SocialProfile] = []
    @StateObject private var socialService = SocialService.shared

    // Platform Lists
    let visualPlatforms = ["Theater", "Netflix", "HBO/Max", "Hulu", "Prime Video", "Apple TV+", "Disney+", "Other", "Not Sure"]
    let audioPlatforms = ["Apple Podcasts", "Spotify", "YouTube", "Overcast", "Pocket Casts", "Other", "Not Sure"]

    var isBook: Bool { movie.mediaType == "book" }
    var isPodcast: Bool { movie.mediaType == "podcast" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        if let path = movie.posterPath, path.contains("http") {
                            AsyncImage(url: URL(string: path)) { phase in
                                if let img = phase.image { img.resizable().scaledToFit() }
                                else { Color.gray.opacity(0.2) }
                            }
                            .frame(width: 60).cornerRadius(8)
                        } else {
                            PosterThumb(posterPath: movie.posterPath, title: movie.title, width: 60)
                        }
                        
                        VStack(alignment: .leading) {
                            Text(movie.title).font(.headline)
                            if let y = movie.year {
                                Text(String(y)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                // DATE SECTION (Layout Fix)
                Section("When") {
                    HStack {
                        if unknownDate {
                            Text("Date Unknown")
                                .foregroundStyle(.secondary)
                                .italic()
                        } else {
                            DatePicker(
                                selection: $watchedOn,
                                displayedComponents: .date
                            ) {
                                Text(isBook ? "Date Read" : "Date Watched")
                            }
                        }

                        Spacer()

                        Button {
                            withAnimation { unknownDate.toggle() }
                        } label: {
                            Text(unknownDate ? "Set Date" : "Don't Remember")
                                .font(.caption).bold()
                                .padding(6)
                                .background(unknownDate ? Color.blue.opacity(0.1) : Color.red.opacity(0.1))
                                .foregroundColor(unknownDate ? .blue : .red)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain) // Prevents clicking the whole row
                    }
                    
                    if isBook {
                        // Book format picker
                        Picker("Format", selection: $selectedBookFormat) {
                            ForEach(BookFormat.allCases, id: \.self) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                    } else {
                        Picker("Platform", selection: $platform) {
                            ForEach(isPodcast ? audioPlatforms : visualPlatforms, id: \.self) { p in
                                Text(p).tag(p)
                            }
                        }
                    }
                }
                
                Section("Social") {
                    // Tag friends button
                    Button {
                        showFriendPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "person.badge.plus").foregroundStyle(.blue)
                            Text("Tag Friends")
                            Spacer()
                            if !taggedUsers.isEmpty {
                                Text("\(taggedUsers.count) tagged")
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    // Show tagged users
                    if !taggedUsers.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(taggedUsers, id: \.id) { user in
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.blue.opacity(0.2))
                                            .frame(width: 24, height: 24)
                                            .overlay(Text(String(user.displayName.prefix(1))).font(.caption2).bold())
                                        Text(user.displayName)
                                            .font(.caption)
                                        Button {
                                            taggedUsers.removeAll { $0.id == user.id }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(16)
                                }
                            }
                        }
                    }

                    // Text field for non-app friends
                    HStack {
                        Image(systemName: "person.2.fill").foregroundStyle(.gray)
                        TextField(isBook || isPodcast ? "Others (not on app)" : "Others not on app?", text: $withWho)
                    }
                }
                
                Section("Notes") {
                    TextField("What did you think?", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(isPodcast ? "Log Podcast" : (isBook ? "Log Book" : "Log Movie"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existingLog == nil ? "Next: Rank" : "Save") { saveLog() }.bold()
                }
            }
            .task {
                let actor = AuthService.shared.sessionActor()
                if let s = try? await actor.session() { userId = s.userId }
                if let existingDate = existingLog?.watchedOn {
                    watchedOn = existingDate
                    unknownDate = false
                }
                if let existingFormat = existingLog?.bookFormat {
                    selectedBookFormat = existingFormat
                }
                // Load following list for tagging
                await socialService.loadFollowing()
            }
            .sheet(isPresented: $showFriendPicker) {
                FriendPickerSheet(taggedUsers: $taggedUsers, userId: userId)
            }
        }
    }
    
    private func saveLog() {
        // Use the current watchedOn state (allows editing dates)
        let finalWatchedOn: Date? = unknownDate ? nil : watchedOn
        
        // Map platform string to WatchLocation
        let watchLocation: WatchLocation? = {
            if isBook { return nil }
            switch platform.lowercased() {
            case "theater": return .theater
            case "not sure": return .notSure
            default: return .other
            }
        }()

        // Collect tagged user IDs
        let taggedIds = taggedUsers.isEmpty ? nil : taggedUsers.map { $0.id.uuidString }

        if let existingLog {
            existingLog.watchedOn = finalWatchedOn
            existingLog.whereWatched = watchLocation
            existingLog.withWho = withWho.isEmpty ? nil : withWho
            existingLog.notes = notes.isEmpty ? nil : notes
            existingLog.taggedUserIds = taggedIds
            if isBook {
                existingLog.bookFormat = selectedBookFormat
            }
        } else {
            let log = LogEntry(
                createdAt: Date(),
                rating: nil,
                watchedOn: finalWatchedOn,
                whereWatched: watchLocation,
                withWho: withWho.isEmpty ? nil : withWho,
                notes: notes.isEmpty ? nil : notes,
                movie: movie,
                ownerId: userId,
                bookFormat: isBook ? selectedBookFormat : nil,
                taggedUserIds: taggedIds
            )
            context.insert(log)
        }
        
        let movieID = movie.id
        let allItems = (try? context.fetch(FetchDescriptor<UserItem>())) ?? []
        if let item = allItems.first(where: { $0.movie?.id == movieID }) {
            item.state = .seen
        } else {
            context.insert(UserItem(movie: movie, state: .seen, ownerId: userId))
        }
        
        try? context.save()

        // Send notifications to tagged users (only for new logs, not edits)
        if existingLog == nil && !taggedUsers.isEmpty {
            Task {
                await sendTagNotifications()
            }
        }

        dismiss()
        if existingLog == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showRanking = true }
        }
    }

    private func sendTagNotifications() async {
        let movieTitle = movie.title
        let mediaWord = movie.mediaType == "book" ? "read" : (movie.mediaType == "podcast" ? "listen" : "watch")

        for taggedUser in taggedUsers {
            let message = "tagged you in their \(mediaWord) of \(movieTitle)"
            await NotificationService.shared.sendNotification(
                to: taggedUser.id,
                type: "tagged",
                message: message,
                relatedId: movie.tmdbID != nil ? UUID() : nil // Use a new UUID since we don't have the log ID yet
            )
        }
    }
}

// MARK: - Friend Picker Sheet
struct FriendPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var taggedUsers: [SocialProfile]
    let userId: String

    @State private var following: [SocialProfile] = []
    @State private var searchText = ""
    @State private var isLoading = true

    var filteredFriends: [SocialProfile] {
        if searchText.isEmpty {
            return following
        }
        return following.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            ($0.username?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack {
                        ProgressView()
                        Text("Loading friends...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if following.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No Friends Yet")
                            .font(.headline)
                        Text("Follow people to tag them when you watch things together!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    List {
                        ForEach(filteredFriends, id: \.id) { friend in
                            TaggableFriendRow(friend: friend, isSelected: taggedUsers.contains { $0.id == friend.id }) {
                                toggleFriend(friend)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, prompt: "Search friends")
                }
            }
            .navigationTitle("Tag Friends")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .bold()
                }
            }
            .task {
                following = await SocialService.shared.fetchFollowing(userId: userId)
                isLoading = false
            }
        }
    }

    private func toggleFriend(_ friend: SocialProfile) {
        if let index = taggedUsers.firstIndex(where: { $0.id == friend.id }) {
            taggedUsers.remove(at: index)
        } else {
            taggedUsers.append(friend)
        }
    }
}

struct TaggableFriendRow: View {
    let friend: SocialProfile
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(String(friend.displayName.prefix(1)).uppercased())
                            .font(.headline)
                            .foregroundStyle(.blue)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                    if let username = friend.username {
                        Text("@\(username)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .secondary.opacity(0.5))
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
