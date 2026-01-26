// DataRepairView.swift
// SAFE VERSION - Removed forced score redistribution!
import SwiftUI
import SwiftData
import Supabase

struct DataRepairView: View {
    @Environment(\.modelContext) private var context
    @State private var logText = "Ready."
    @State private var currentUserId = "Loading..."
    @State private var isWorking = false
    
    // Live Stats
    @Query private var allUserItems: [UserItem]
    @Query private var allMovies: [Movie]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Hard Sync Tool")
                    .font(.largeTitle).bold()
                
                // IDENTITY CHECK
                VStack(spacing: 8) {
                    Text("LOGGED IN AS:")
                        .font(.caption).bold().foregroundStyle(.secondary)
                    Text(currentUserId)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    
                    if currentUserId == "guest" {
                        Text("⚠️ You must Sign In on the Profile tab first!")
                            .font(.caption).bold().foregroundStyle(.red)
                    }
                }
                .padding()
                
                List {
                    Section("Phone Database (Local)") {
                        Text("Movies on Phone: \(allMovies.count)")
                        Text("Library Items: \(allUserItems.count)")
                    }
                    
                    Section("Actions") {
                        Button {
                            Task { await uploadToCloud() }
                        } label: {
                            Label("Upload Local Data to Cloud", systemImage: "icloud.and.arrow.up")
                        }
                        .foregroundStyle(.blue)
                        .disabled(isWorking || currentUserId == "guest")
                        
                        Button {
                            Task { await hardSync() }
                        } label: {
                            Label("Wipe Local & Download from Cloud", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                        }
                        .foregroundStyle(.red)
                        .disabled(isWorking || currentUserId == "guest")
                    }
                    
                    // REMOVED: The "Migrate Score Distribution" button that was ruining your rankings!
                    // That button forced all scores into a bell curve (85-99, 25-85, 1-25)
                    // Your natural rankings are better without it!
                    
                    Section("Log") {
                        if isWorking { ProgressView().padding(.bottom, 8) }
                        Text(logText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task {
                let actor = AuthService.shared.sessionActor()
                if let s = try? await actor.session() {
                    currentUserId = s.userId
                } else {
                    currentUserId = "guest"
                }
            }
        }
    }
    
    // MARK: - UPLOAD TO CLOUD
    private func uploadToCloud() async {
        isWorking = true
        logText = "Starting Upload to Cloud...\n"
        
        guard let client = AuthService.shared.client else {
            logText += "❌ Error: No Cloud Connection."
            isWorking = false
            return
        }
        
        guard let userUUID = UUID(uuidString: currentUserId) else {
            logText += "❌ Error: Invalid user ID."
            isWorking = false
            return
        }
        
        logText += "📦 Collecting local data...\n"
        
        // Get all local logs
        let allLocalLogs = try? context.fetch(FetchDescriptor<LogEntry>())
        let myLogs = (allLocalLogs ?? []).filter { $0.ownerId == currentUserId }
        
        logText += "Found \(myLogs.count) local logs to upload.\n"
        
        var uploadedCount = 0
        var errorCount = 0
        
        for (index, log) in myLogs.enumerated() {
            guard let movie = log.movie else { continue }
            
            // Check if already in cloud
            do {
                let existing: [CloudLog] = try await client
                    .from("logs")
                    .select("*")
                    .eq("user_id", value: userUUID)
                    .eq("title", value: movie.title)
                    .limit(1)
                    .execute()
                    .value
                
                if !existing.isEmpty {
                    // Already in cloud, skip
                    continue
                }
                
                // Upload to cloud - create encodable struct
                struct LogUpload: Encodable {
                    let id: String
                    let user_id: String
                    let title: String
                    let year: Int?
                    let tmdb_id: Int?
                    let poster_path: String?
                    let media_type: String
                    let watched_on: String?
                    let notes: String?
                    let created_at: String
                }
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                
                let logUpload = LogUpload(
                    id: UUID().uuidString,
                    user_id: userUUID.uuidString,
                    title: movie.title,
                    year: movie.year,
                    tmdb_id: movie.tmdbID,
                    poster_path: movie.posterPath,
                    media_type: movie.mediaType,
                    watched_on: log.watchedOn.map { dateFormatter.string(from: $0) },
                    notes: log.notes,
                    created_at: isoFormatter.string(from: log.createdAt)
                )
                
                try await client
                    .from("logs")
                    .insert(logUpload)
                    .execute()
                
                uploadedCount += 1
                
                if index % 10 == 0 {
                    logText += "Uploaded \(uploadedCount)/\(myLogs.count)...\n"
                }
                
            } catch {
                errorCount += 1
                if errorCount < 5 {
                    logText += "❌ Error uploading \(movie.title): \(error.localizedDescription)\n"
                }
            }
        }
        
        logText += "✅ Upload complete! Uploaded \(uploadedCount) items. Errors: \(errorCount)\n"
        isWorking = false
    }
    
    // MARK: - THE HARD SYNC
    private func hardSync() async {
        isWorking = true
        logText = "Starting Hard Sync...\n"
        
        guard let client = AuthService.shared.client else {
            logText += "❌ Error: No Cloud Connection."
            isWorking = false
            return
        }
        
        // 1. NUKE LOCAL DATA
        logText += "🗑️ Deleting local data...\n"
        try? context.delete(model: Movie.self)
        try? context.delete(model: Score.self)
        try? context.delete(model: UserItem.self)
        try? context.delete(model: LogEntry.self)
        try? context.save()
        
        // 2. FETCH FROM CLOUD (WITH PAGINATION)
        logText += "☁️ Downloading from Cloud...\n"
        
        var allCloudLogs: [CloudLog] = []
        var offset = 0
        let batchSize = 1000
        
        do {
            // Keep fetching until we get less than batchSize
            while true {
                let batch: [CloudLog] = try await client
                    .from("logs")
                    .select("*")
                    .eq("user_id", value: currentUserId)
                    .range(from: offset, to: offset + batchSize - 1)
                    .execute()
                    .value
                
                allCloudLogs.append(contentsOf: batch)
                logText += "Downloaded \(allCloudLogs.count) records so far...\n"
                
                if batch.count < batchSize {
                    // Last batch, we're done
                    break
                }
                
                offset += batchSize
            }
            
            logText += "Found \(allCloudLogs.count) total records in cloud.\n"
            
            // 3. REBUILD LOCAL DB
            for (index, log) in allCloudLogs.enumerated() {
                // Create Movie
                let movie = Movie(
                    title: log.title,
                    year: log.year,
                    tmdbID: log.tmdbId,
                    posterPath: log.posterPath,
                    genreIDs: [],
                    mediaType: log.mediaType ?? "movie",
                    ownerId: currentUserId
                )
                context.insert(movie)
                
                // Create Library Item (Seen)
                let item = UserItem(movie: movie, state: .seen, ownerId: currentUserId)
                context.insert(item)
                
                // Create Score
                if let s = log.score {
                    let score = Score(movieID: movie.id, display100: s, latent: 0, variance: 0, ownerId: currentUserId)
                    context.insert(score)
                }
                
                // Create Log Entry
                let entry = LogEntry(watchedOn: log.watchedOn, notes: log.notes, movie: movie, ownerId: currentUserId)
                context.insert(entry)
                
                // Save in batches to avoid memory issues
                if index % 100 == 0 {
                    try? context.save()
                    logText += "Saved \(index) items...\n"
                }
            }
            
            // 4. FINAL SAVE
            try context.save()
            logText += "✅ SUCCESS! Saved \(allCloudLogs.count) items to phone."
            
        } catch {
            logText += "❌ Error: \(error.localizedDescription)"
        }
        
        isWorking = false
    }
}
