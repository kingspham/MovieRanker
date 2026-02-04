// App.swift
// Main app entry with theme support

import SwiftUI
import SwiftData
import Combine

// MARK: - Theme Manager
enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @AppStorage("appTheme") var storedTheme: String = AppTheme.system.rawValue

    @Published private var _themeUpdated = false

    var currentTheme: AppTheme {
        get { AppTheme(rawValue: storedTheme) ?? .system }
        set {
            storedTheme = newValue.rawValue
            _themeUpdated.toggle()
        }
    }

    var colorScheme: ColorScheme? {
        currentTheme.colorScheme
    }

    private init() {}
}

// MARK: - App Entry
@main
struct AppEntry: App {
    @StateObject private var themeManager = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            RootEntryView()
                .preferredColorScheme(themeManager.colorScheme)
                .environmentObject(themeManager)
        }
        .modelContainer(for: [
            Movie.self,
            UserItem.self,
            Score.self,
            LogEntry.self,
            CustomList.self,
            UserReview.self
        ], inMemory: false)
    }
}

// Separate view to handle the async auth check on launch
private struct RootEntryView: View {
    @State private var appState: AppState = .loading
    @Environment(\.modelContext) private var context

    enum AppState {
        case loading
        case authenticated
        case unauthenticated
    }

    var body: some View {
        Group {
            switch appState {
            case .loading:
                ZStack {
                    Color(uiColor: .systemBackground).ignoresSafeArea()
                    VStack(spacing: 24) {
                        Image(systemName: "film.stack.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.yellow)
                            .symbolEffect(.bounce, value: true)

                        Text("Loading Library...")
                            .font(.headline)
                            .foregroundColor(Color(uiColor: .label))

                        ProgressView()
                    }
                }
            case .authenticated:
                AppMainView()
            case .unauthenticated:
                AuthenticationView()
            }
        }
        .task {
            // 1. Wait a moment to let the UI render first
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s

            // 2. Initialize Auth
            print("🔐 Bootstrapping Auth...")
            await AuthService.shared.bootstrap()

            // 3. Check Session
            let actor = AuthService.shared.sessionActor()
            if let _ = try? await actor.session() {
                print("👤 User found.")
                withAnimation { appState = .authenticated }
            } else {
                print("🤷‍♂️ No user found.")
                withAnimation { appState = .unauthenticated }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .continueAsGuest)) { _ in
            withAnimation { appState = .authenticated }
        }
        .onReceive(NotificationCenter.default.publisher(for: .userDidSignOut)) { _ in
            withAnimation { appState = .unauthenticated }
        }
        .onReceive(NotificationCenter.default.publisher(for: .userDidSignIn)) { _ in
            withAnimation { appState = .authenticated }
        }
    }
}

private struct AppMainView: View {
    @StateObject private var notifService = NotificationService.shared
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("lastSyncTime") private var lastSyncTime: Double = 0

    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label(L10n.activity, systemImage: "bubble.left.and.bubble.right.fill") }
                .badge(notifService.unreadCount > 0 ? notifService.unreadCount : 0)

            SearchView()
                .tabItem { Label(L10n.explore, systemImage: "magnifyingglass") }

            LeaderboardView()
                .tabItem { Label(L10n.rankings, systemImage: "trophy.fill") }

            YourListView()
                .tabItem { Label(L10n.library, systemImage: "books.vertical.fill") }

            ProfileView()
                .tabItem { Label(L10n.profile, systemImage: "person.crop.circle") }
        }
        .task {
            await notifService.fetchNotifications()

            // Auto-sync on launch if it's been more than 5 minutes since last sync
            let fiveMinutes: Double = 300
            let now = Date().timeIntervalSince1970
            if now - lastSyncTime > fiveMinutes {
                print("🔄 Auto-syncing from cloud...")
                await ScoreService.shared.syncScores(context: context)
                await UserItemService.shared.syncUserItems(context: context)
                await ListService.shared.syncLists(context: context)
                lastSyncTime = now
                print("✅ Auto-sync complete")
            }
        }
        .task {
            // Poll for new notifications every 5 minutes (reduced from 30s to save battery/network)
            // The NotificationService also has internal caching/backoff for failed requests
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes
                guard !Task.isCancelled else { break }
                await notifService.fetchNotifications()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Refresh notifications when app becomes active
            if newPhase == .active {
                Task {
                    await notifService.fetchNotifications()
                }
            }
        }
    }
}

extension Notification.Name {
    static let continueAsGuest = Notification.Name("continueAsGuest")
    static let userDidSignOut  = Notification.Name("userDidSignOut")
    static let userDidSignIn   = Notification.Name("userDidSignIn")
}
