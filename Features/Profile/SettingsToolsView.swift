// SettingsToolsView.swift
// Simplified version for regular users

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsToolsView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var importService = ImportService.shared

    @State private var showingFilePicker = false
    @State private var showingImportOptions = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var userId = "guest"
    @AppStorage("appLanguage") private var appLanguage: String = "en"

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
                    Text(L10n.appearance)
                } footer: {
                    Text("System follows your device's dark mode setting")
                }

                // LANGUAGE SECTION
                Section {
                    Picker(L10n.language, selection: $appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            HStack {
                                Text(lang.flag)
                                Text(lang.displayName)
                            }
                            .tag(lang.rawValue)
                        }
                    }
                } header: {
                    Text(L10n.language)
                } footer: {
                    Text(L10n.languageFooter)
                }

                // CURRENT STATUS
                Section {
                    HStack {
                        Text(L10n.rankedItems)
                        Spacer()
                        Text("\(allUserItems.filter { $0.state == .seen }.count)")
                            .foregroundStyle(.blue)
                    }

                    HStack {
                        Text(L10n.watchlist)
                        Spacer()
                        Text("\(allUserItems.filter { $0.state == .watchlist }.count)")
                            .foregroundStyle(.green)
                    }

                    HStack {
                        Text(L10n.logEntries)
                        Spacer()
                        Text("\(allLogs.count)")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text(L10n.yourStats)
                }

                // IMPORT
                Section {
                    Button {
                        showingImportOptions = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            VStack(alignment: .leading) {
                                Text("Import Watch History")
                                Text("Netflix or Letterboxd")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
                    Text(L10n.importData)
                } footer: {
                    Text(L10n.isSpanish ? "Importa tu historial de visualización de servicios de streaming" : "Import your viewing history from streaming services")
                }

                // QUICK ACTIONS
                Section {
                    NavigationLink {
                        BulkRankingView()
                    } label: {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                            VStack(alignment: .leading) {
                                Text("Rank Unranked Items")
                                Text("Quick-rank items in your history")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button {
                        Task { await fixDocumentaryClassification() }
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                            VStack(alignment: .leading) {
                                Text("Fix Documentary Classification")
                                Text("Re-fetch genres for movies with missing data")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(L10n.quickActions)
                }

                // ABOUT
                Section {
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                       let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                        HStack {
                            Text(L10n.version)
                            Spacer()
                            Text("\(version) (\(build))")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(L10n.about)
                }
            }
            .navigationTitle(L10n.settings)
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result: result)
            }
            .sheet(isPresented: $showingImportOptions) {
                ImportOptionsSheet(
                    onSelectFile: {
                        showingImportOptions = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingFilePicker = true
                        }
                    }
                )
            }
            .alert("Import Complete", isPresented: $showAlert) {
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
                alertMessage = importService.message
                showAlert = true
            }

        case .failure(let error):
            alertMessage = "Import failed: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func fixDocumentaryClassification() async {
        let allMovies = (try? context.fetch(FetchDescriptor<Movie>())) ?? []
        let moviesNeedingGenres = allMovies.filter { $0.genreIDs.isEmpty && $0.tmdbID != nil && $0.mediaType == "movie" }

        guard !moviesNeedingGenres.isEmpty else {
            await MainActor.run {
                alertMessage = "All movies already have genre data!"
                showAlert = true
            }
            return
        }

        var fixedCount = 0
        let client = try? TMDbClient()

        for movie in moviesNeedingGenres.prefix(50) { // Limit to 50 to avoid rate limits
            guard let tmdbID = movie.tmdbID, let client = client else { continue }

            do {
                let details = try await client.getDetails(id: tmdbID, type: "movie")
                if let genres = details.genres {
                    let genreIds = genres.map { $0.id }
                    await MainActor.run {
                        movie.genreIDs = genreIds
                    }
                    fixedCount += 1
                }
            } catch {
                print("Failed to fetch genres for \(movie.title): \(error)")
            }

            // Small delay to avoid rate limiting
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        try? context.save()

        await MainActor.run {
            alertMessage = "Fixed \(fixedCount) movies! Documentaries (genre 99) will now be properly classified."
            showAlert = true
        }
    }
}

// MARK: - Import Options Sheet
struct ImportOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let onSelectFile: () -> Void

    var body: some View {
        NavigationStack {
            List {
                // Netflix Section
                Section {
                    Button {
                        if let url = URL(string: "https://www.netflix.com/account/getmyinfo") {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "play.rectangle.fill")
                                .foregroundStyle(.red)
                                .font(.title2)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Netflix")
                                    .font(.headline)
                                Text("Open Netflix data request page")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Netflix")
                } footer: {
                    Text("Request your data from Netflix, then download ViewingActivity.csv from the email they send you.")
                }

                // Letterboxd Section
                Section {
                    Button {
                        if let url = URL(string: "https://letterboxd.com/settings/data/") {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "film.stack")
                                .foregroundStyle(.green)
                                .font(.title2)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Letterboxd")
                                    .font(.headline)
                                Text("Open Letterboxd export page")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Letterboxd")
                } footer: {
                    Text("Export your data from Letterboxd and use the diary.csv file.")
                }

                // Select File Section
                Section {
                    Button {
                        dismiss()
                        onSelectFile()
                    } label: {
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(.blue)
                                .font(.title2)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("I Already Have a File")
                                    .font(.headline)
                                Text("Select a CSV file from your device")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Import File")
                } footer: {
                    Text("If you've already downloaded your viewing history, tap here to select the file.")
                }
            }
            .navigationTitle("Import History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsToolsView()
}
