// SettingsToolsView.swift
// COMPLETE VERSION with ALL fix buttons

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsToolsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var themeManager: ThemeManager
    @StateObject private var importService = ImportService.shared
    @StateObject private var badgeService = BadgeService.shared

    @State private var showingFilePicker = false
    @State private var showingCSVPicker = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var userId = "guest"

    @Query private var allLogs: [LogEntry]
    @Query private var allUserItems: [UserItem]
    @Query private var allScores: [Score]

    var body: some View {
        NavigationStack {
            List {
                // APPEARANCE SECTION
                Section {
                    Picker("Theme", selection: Binding(
                        get: { themeManager.currentTheme },
                        set: { themeManager.currentTheme = $0 }
                    )) {
                        ForEach(AppTheme.allCases) { theme in
                            Label(theme.rawValue, systemImage: theme.icon)
                                .tag(theme)
                        }
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("System follows your device's dark mode setting")
                }

                // QUICK FIXES SECTION
                Section {
                    // Recalculate scores with new algorithm
                    Button {
                        Task {
                            await RecalculateAllScores.recalculateAllUserScores(context: context)
                            alertMessage = "All scores recalculated! Check console for details."
                            showAlert = true
                        }
                    } label: {
                        Label("Recalculate All Scores", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.blue)
                    }
                    
                    // Fix watch dates from CSV
                    Button {
                        showingCSVPicker = true
                    } label: {
                        Label("Fix Watch Dates from CSV", systemImage: "calendar")
                            .foregroundStyle(.orange)
                    }
                    
                    // Complete fix
                    Button {
                        Task {
                            await CompleteFix.fixEverything(context: context)
                            alertMessage = "Complete fix done! Check console."
                            showAlert = true
                        }
                    } label: {
                        Label("Run Complete Fix", systemImage: "hammer.fill")
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("Quick Fixes")
                } footer: {
                    Text("Recalculate Scores: Applies new algorithm to all existing rankings\nFix Dates: Updates LogEntries with dates from Netflix CSV\nComplete Fix: Runs all migrations")
                }
                
                // CURRENT STATUS
                Section {
                    HStack {
                        Text("User ID:")
                        Spacer()
                        Text(userId.prefix(8) + "...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Seen Items:")
                        Spacer()
                        Text("\(allUserItems.filter { $0.state == .seen }.count)")
                            .foregroundStyle(.blue)
                    }
                    
                    HStack {
                        Text("Log Entries:")
                        Spacer()
                        Text("\(allLogs.count)")
                            .foregroundStyle(.green)
                    }
                    
                    HStack {
                        Text("Scores:")
                        Spacer()
                        Text("\(allScores.count)")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Current Status")
                }
                
                // IMPORT
                Section {
                    Button {
                        showingFilePicker = true
                    } label: {
                        Label("Import from Netflix/Letterboxd", systemImage: "square.and.arrow.down")
                    }
                    .disabled(importService.isRunning)
                    
                    if importService.isRunning {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: importService.progress)
                            Text(importService.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Import")
                }
                
                // BULK RANKING
                Section {
                    NavigationLink {
                        BulkRankingView()
                    } label: {
                        Label("Rank Unranked Items", systemImage: "chart.bar.fill")
                    }
                } header: {
                    Text("Ranking")
                }
                
                // OTHER TOOLS
                Section {
                    NavigationLink {
                        DataRepairView()
                    } label: {
                        Label("Cloud Recovery", systemImage: "arrow.triangle.2.circlepath")
                    }
                    
                    Button {
                        recalculateBadges()
                    } label: {
                        Label("Recalculate Badges", systemImage: "medal.fill")
                    }
                    
                    Button {
                        Task { await syncScores() }
                    } label: {
                        Label("Sync Scores", systemImage: "arrow.down.circle")
                    }
                } header: {
                    Text("Other Tools")
                }
            }
            .navigationTitle("Tools & Settings")
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result: result)
            }
            .fileImporter(
                isPresented: $showingCSVPicker,
                allowedContentTypes: [.commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                handleCSVForDateFix(result: result)
            }
            .alert("Complete", isPresented: $showAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .task {
                userId = AuthService.shared.currentUserId() ?? "guest"
            }
        }
    }
    
    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                alertMessage = "Failed to access file"
                showAlert = true
                return
            }
            
            defer { url.stopAccessingSecurityScopedResource() }
            
            guard let data = try? Data(contentsOf: url) else {
                alertMessage = "Failed to read file"
                showAlert = true
                return
            }
            
            Task {
                await importService.runImport(data: data, context: context)
                alertMessage = importService.message + "\n\nRun 'Complete Fix' after import!"
                showAlert = true
            }
            
        case .failure(let error):
            alertMessage = "Import failed: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    private func handleCSVForDateFix(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                alertMessage = "Failed to access file"
                showAlert = true
                return
            }
            
            defer { url.stopAccessingSecurityScopedResource() }
            
            guard let data = try? Data(contentsOf: url) else {
                alertMessage = "Failed to read file"
                showAlert = true
                return
            }
            
            Task {
                await FixWatchDatesFromCSV.fixDatesFromNetflixCSV(csvData: data, context: context)
                alertMessage = "Watch dates fixed! Check console for details."
                showAlert = true
            }
            
        case .failure(let error):
            alertMessage = "CSV read failed: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    private func recalculateBadges() {
        let inputs = allLogs.compactMap { log -> BadgeInput? in
            guard let movie = log.movie else { return nil }
            return BadgeInput(watchedOn: log.watchedOn, genreIDs: movie.genreIDs)
        }
        badgeService.calculateBadges(inputs: inputs)
        alertMessage = "Badges recalculated from \(inputs.count) logs!"
        showAlert = true
    }
    
    private func syncScores() async {
        await ScoreService.shared.syncScores(context: context)
        alertMessage = "Scores synced!"
        showAlert = true
    }
}

#Preview {
    SettingsToolsView()
}
