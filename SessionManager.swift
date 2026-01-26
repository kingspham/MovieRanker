import Foundation
import Combine
import Supabase

@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published private(set) var isConfigured = false
    @Published private(set) var userId: String? = nil
    @Published private(set) var email: String? = nil
    @Published private(set) var isLoading = false
    @Published var authErrorMessage: String? = nil

    // Real client (no stub type)
    private(set) var client: SupabaseClient?

    private init() {}

    func configureIfNeeded() {
        guard !isConfigured else { return }
        
        // Improved error checking
        guard let urlStr = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !urlStr.isEmpty else {
            authErrorMessage = "Missing or empty SUPABASE_URL in Info.plist"
            print("[SessionManager] Configuration error: \(authErrorMessage ?? "")")
            return
        }
        
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty else {
            authErrorMessage = "Missing or empty SUPABASE_ANON_KEY in Info.plist"
            print("[SessionManager] Configuration error: \(authErrorMessage ?? "")")
            return
        }
        
        guard let url = URL(string: urlStr) else {
            authErrorMessage = "Invalid SUPABASE_URL format: \(urlStr)"
            print("[SessionManager] Configuration error: \(authErrorMessage ?? "")")
            return
        }
        
        client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        isConfigured = true
        print("[SessionManager] Successfully configured Supabase client")
        
        Task { await refreshSession() }
    }

    func refreshSession() async {
        configureIfNeeded()
        guard let client else { return }
        
        // Check if user is logged in
        if let user = client.auth.currentUser {
            userId = user.id.uuidString
            email = user.email
            print("[SessionManager] Session refreshed for user: \(email ?? "unknown")")
        } else {
            userId = nil
            email = nil
            print("[SessionManager] No active session")
        }
    }

    func signUp(email: String, password: String) async {
        configureIfNeeded()
        guard let client else { return }
        isLoading = true
        do {
            let result = try await client.auth.signUp(email: email, password: password)
            // If sign-up also signs the user in, capture the session/user
            let user = result.user
            userId = user.id.uuidString
            self.email = user.email
            authErrorMessage = nil
            print("[SessionManager] Signed up: \(self.email ?? "unknown")")
        } catch {
            authErrorMessage = error.localizedDescription
            print("[SessionManager] Sign-up error: \(error.localizedDescription)")
        }
        isLoading = false
    }

    func signIn(email: String, password: String) async {
        configureIfNeeded()
        guard let client else { return }
        isLoading = true
        do {
            _ = try await client.auth.signIn(email: email, password: password)
            await refreshSession()
        } catch {
            authErrorMessage = error.localizedDescription
            print("[SessionManager] Sign-in error: \(error.localizedDescription)")
        }
        isLoading = false
    }

    func signOut() async {
        configureIfNeeded()
        guard let client else { return }
        do {
            try await client.auth.signOut()
            userId = nil
            email = nil
            authErrorMessage = nil
            print("[SessionManager] Signed out")
        } catch {
            authErrorMessage = error.localizedDescription
            print("[SessionManager] Sign-out error: \(error.localizedDescription)")
        }
    }
    
    func setGuestMode() async {
        userId = "guest"
        email = nil
        authErrorMessage = nil
        print("[SessionManager] Set to guest mode: \(userId ?? "unknown")")
    }
}
