// DiagnosticView.swift
// ADD THIS FILE to Features/Profile folder
// Shows exactly what's in your database

import SwiftUI
import SwiftData

struct DiagnosticView: View {
    @Environment(\.modelContext) private var context
    
    @Query private var allUserItems: [UserItem]
    @Query private var allLogs: [LogEntry]
    @Query private var allScores: [Score]
    @Query private var allMovies: [Movie]
    
    @State private var userId: String = "guest"
    
    var body: some View {
        List {
            Section("User Info") {
                HStack {
                    Text("Current User ID:")
                    Spacer()
                    Text(userId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("UserItems (Seen/Watchlist)") {
                HStack {
                    Text("Total UserItems:")
                    Spacer()
                    Text("\(allUserItems.count)")
                }
                
                HStack {
                    Text("Owned by 'guest':")
                    Spacer()
                    Text("\(allUserItems.filter { $0.ownerId == "guest" }.count)")
                        .foregroundStyle(.orange)
                }
                
                HStack {
                    Text("Owned by current user:")
                    Spacer()
                    Text("\(allUserItems.filter { $0.ownerId == userId }.count)")
                        .foregroundStyle(.blue)
                }
                
                HStack {
                    Text("State = seen:")
                    Spacer()
                    Text("\(allUserItems.filter { $0.state == .seen }.count)")
                        .foregroundStyle(.green)
                }
            }
            
            Section("LogEntries") {
                HStack {
                    Text("Total LogEntries:")
                    Spacer()
                    Text("\(allLogs.count)")
                }
                
                HStack {
                    Text("Owned by 'guest':")
                    Spacer()
                    Text("\(allLogs.filter { $0.ownerId == "guest" }.count)")
                        .foregroundStyle(.orange)
                }
                
                HStack {
                    Text("Owned by current user:")
                    Spacer()
                    Text("\(allLogs.filter { $0.ownerId == userId }.count)")
                        .foregroundStyle(.blue)
                }
                
                HStack {
                    Text("With dates:")
                    Spacer()
                    Text("\(allLogs.filter { $0.watchedOn != nil }.count)")
                        .foregroundStyle(.green)
                }
                
                HStack {
                    Text("Without dates:")
                    Spacer()
                    Text("\(allLogs.filter { $0.watchedOn == nil }.count)")
                        .foregroundStyle(.red)
                }
            }
            
            Section("Scores") {
                HStack {
                    Text("Total Scores:")
                    Spacer()
                    Text("\(allScores.count)")
                }
                
                HStack {
                    Text("Owned by 'guest':")
                    Spacer()
                    Text("\(allScores.filter { $0.ownerId == "guest" }.count)")
                        .foregroundStyle(.orange)
                }
                
                HStack {
                    Text("Owned by current user:")
                    Spacer()
                    Text("\(allScores.filter { $0.ownerId == userId }.count)")
                        .foregroundStyle(.blue)
                }
            }
            
            Section("Movies") {
                HStack {
                    Text("Total Movies:")
                    Spacer()
                    Text("\(allMovies.count)")
                }
                
                HStack {
                    Text("Owned by 'guest':")
                    Spacer()
                    Text("\(allMovies.filter { $0.ownerId == "guest" }.count)")
                        .foregroundStyle(.orange)
                }
                
                HStack {
                    Text("Owned by current user:")
                    Spacer()
                    Text("\(allMovies.filter { $0.ownerId == userId }.count)")
                        .foregroundStyle(.blue)
                }
            }
            
            Section("Sample Data") {
                if let firstLog = allLogs.first {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("First LogEntry:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Movie: \(firstLog.movie?.title ?? "nil")")
                            .font(.caption)
                        Text("Owner: \(firstLog.ownerId)")
                            .font(.caption)
                        Text("Date: \(firstLog.watchedOn?.formatted() ?? "nil")")
                            .font(.caption)
                    }
                }
                
                if let firstScore = allScores.first {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("First Score:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Value: \(firstScore.display100)")
                            .font(.caption)
                        Text("Owner: \(firstScore.ownerId)")
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Database Diagnostic")
        .task {
            userId = AuthService.shared.currentUserId() ?? "guest"
        }
    }
}

#Preview {
    DiagnosticView()
}
