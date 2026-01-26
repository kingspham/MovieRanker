import Foundation
import Supabase

@MainActor
final class AuthService {
    static let shared = AuthService()

    private(set) var client: SupabaseClient!
    private let sessionManager = AppSessionManager()

    private init() {
        // Use Config instead of loose Strings
        guard let url = URL(string: Config.supabaseUrl) else {
            print("❌ Supabase URL invalid")
            return
        }
        
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: Config.supabaseAnonKey,
            options: .init(
                auth: .init(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    func sessionActor() -> AppSessionManager { sessionManager }

    func bootstrap() async {
        if let s = try? await client.auth.session {
            await sessionManager.set(accessToken: s.accessToken, userId: s.user.id.uuidString)
        } else {
            await sessionManager.clear()
        }

        Task.detached { [weak self] in
            guard let self else { return }
            for await (_, session) in await self.client.auth.authStateChanges {
                _ = await MainActor.run {
                    if let s = session {
                        Task { await self.sessionManager.set(accessToken: s.accessToken, userId: s.user.id.uuidString) }
                        NotificationCenter.default.post(name: .userDidSignIn, object: nil)
                    } else {
                        Task { await self.sessionManager.clear() }
                        NotificationCenter.default.post(name: .userDidSignOut, object: nil)
                    }
                }
            }
        }
    }

    // MARK: - Auth Actions

    func signIn(email: String, password: String) async throws {
        _ = try await client.auth.signIn(email: email, password: password)
    }
    
    func signUp(email: String, password: String) async throws {
        _ = try await client.auth.signUp(email: email, password: password)
    }

    func signOut() async throws {
        try await client.auth.signOut()
        await sessionManager.clear()
    }
    
    /// Returns the current authenticated user's ID as a string, or nil if not signed in
    func currentUserId() -> String? {
        return client.auth.currentUser?.id.uuidString
    }
}
