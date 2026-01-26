import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var router = AppRouter.shared
    @Environment(\.modelContext) private var context
    
    var body: some View {
        Group {
            if sessionManager.userId != nil {
                RootTabView()
            } else {
                AuthenticationView()
            }
        }
        .environmentObject(router)
        .onAppear {
            sessionManager.configureIfNeeded()
            // One-time owner fix for legacy records with nil ownerId
            let owner = sessionManager.userId ?? "guest"
            MigrationService.runOnLaunch(context: context, owner: owner)
        }
    }
}

#Preview { ContentView() }
