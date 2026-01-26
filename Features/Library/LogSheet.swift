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
    
    // Platform Lists
    let visualPlatforms = ["Theater", "Netflix", "HBO/Max", "Hulu", "Prime Video", "Apple TV+", "Disney+", "Other"]
    let audioPlatforms = ["Apple Podcasts", "Spotify", "YouTube", "Overcast", "Pocket Casts", "Other"]
    
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
                        if let lockedDate = existingLog?.watchedOn {
                            Text("\(isBook ? "Read" : "Watched") \(lockedDate.formatted(date: .abbreviated, time: .omitted))")
                                .foregroundStyle(.secondary)
                        } else if unknownDate {
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
                        
                        if existingLog?.watchedOn == nil {
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
                    }
                    
                    if !isBook {
                        Picker("Platform", selection: $platform) {
                            ForEach(isPodcast ? audioPlatforms : visualPlatforms, id: \.self) { p in
                                Text(p).tag(p)
                            }
                        }
                    }
                }
                
                Section("Social") {
                    HStack {
                        Image(systemName: "person.2.fill").foregroundStyle(.blue)
                        TextField(isBook || isPodcast ? "With whom? (Club/Group)" : "Watched with?", text: $withWho)
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
                    Button("Next: Rank") { saveLog() }.bold()
                }
            }
            .task {
                let actor = AuthService.shared.sessionActor()
                if let s = try? await actor.session() { userId = s.userId }
                if let existingDate = existingLog?.watchedOn {
                    watchedOn = existingDate
                    unknownDate = false
                }
            }
        }
    }
    
    private func saveLog() {
        let finalWatchedOn: Date? = {
            if let existingDate = existingLog?.watchedOn {
                return existingDate
            }
            return unknownDate ? nil : watchedOn
        }()
        
        if let existingLog {
            existingLog.watchedOn = finalWatchedOn
            existingLog.whereWatched = isBook ? nil : WatchLocation(rawValue: platform.lowercased()) ?? .other
            existingLog.withWho = withWho.isEmpty ? nil : withWho
            existingLog.notes = notes.isEmpty ? nil : notes
        } else {
            let log = LogEntry(
                createdAt: Date(),
                rating: nil,
                watchedOn: finalWatchedOn,
                whereWatched: isBook ? nil : WatchLocation(rawValue: platform.lowercased()) ?? .other,
                withWho: withWho.isEmpty ? nil : withWho,
                notes: notes.isEmpty ? nil : notes,
                movie: movie,
                ownerId: userId
            )
            context.insert(log)
        }
        
        let movieID = movie.id
        let predicate = #Predicate<UserItem> { $0.movie?.id == movieID }
        if let item = try? context.fetch(FetchDescriptor(predicate: predicate)).first {
            item.state = .seen
        } else {
            context.insert(UserItem(movie: movie, state: .seen, ownerId: userId))
        }
        
        try? context.save()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showRanking = true }
    }
}
