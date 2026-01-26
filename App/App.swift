// App.swift
// Main app entry with theme support

import SwiftUI
import SwiftData

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

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @AppStorage("appTheme") var storedTheme: String = AppTheme.system.rawValue {
        didSet { objectWillChange.send() }
    }

    var currentTheme: AppTheme {
        get { AppTheme(rawValue: storedTheme) ?? .system }
        set { storedTheme = newValue.rawValue }
    }

    var colorScheme: ColorScheme? {
        currentTheme.colorScheme
    }

    private init() {}
}

// MARK: - Theme-Aware Colors
extension Color {
    static var adaptiveBackground: Color {
        Color(uiColor: .systemBackground)
    }

    static var adaptiveSecondaryBackground: Color {
        Color(uiColor: .secondarySystemBackground)
    }

    static var adaptiveGroupedBackground: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    static var adaptiveLabel: Color {
        Color(uiColor: .label)
    }

    static var adaptiveSecondaryLabel: Color {
        Color(uiColor: .secondaryLabel)
    }
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
                    Color.adaptiveBackground.ignoresSafeArea()
                    VStack(spacing: 24) {
                        Image(systemName: "film.stack.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.yellow)
                            .symbolEffect(.bounce, value: true)

                        Text("Loading Library...")
                            .font(.headline)
                            .foregroundStyle(.adaptiveLabel)

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
    
    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Activity", systemImage: "bubble.left.and.bubble.right.fill") }
                .badge(notifService.unreadCount > 0 ? notifService.unreadCount : 0)
            
            SearchView()
                .tabItem { Label("Explore", systemImage: "magnifyingglass") }
            
            // MOVED: Leaderboard now in main tab bar
            LeaderboardView()
                .tabItem { Label("Rankings", systemImage: "trophy.fill") }
            
            YourListView()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
            
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .task {
            await notifService.fetchNotifications()
        }
    }
}

extension Notification.Name {
    static let continueAsGuest = Notification.Name("continueAsGuest")
    static let userDidSignOut  = Notification.Name("userDidSignOut")
    static let userDidSignIn   = Notification.Name("userDidSignIn")
}
