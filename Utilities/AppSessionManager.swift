import Foundation

enum AuthError: Error { case sessionMissing }

struct AppSession: Sendable {
    let accessToken: String
    let userId: String
}

/// Your app's stable facade around whatever auth backend you use.
/// Replacing Supabase later won't ripple through the app.
actor SessionManager {
    private var current: AppSession?

    func set(accessToken: String, userId: String) {
        current = AppSession(accessToken: accessToken, userId: userId)
    }

    func session() async throws -> AppSession {
        guard let s = current else { throw AuthError.sessionMissing }
        return s
    }

    func clear() { current = nil }
}
