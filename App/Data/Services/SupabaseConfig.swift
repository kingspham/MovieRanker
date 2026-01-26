import Foundation

/// Centralized Supabase configuration for the app.
///
/// These values should match the entries in your Info.plist:
/// - SUPABASE_URL
/// - SUPABASE_ANON_KEY
///
/// The file reads them once at launch and exposes them as static constants.
enum SupabaseConfig {
    /// The base Supabase project URL.
    static let url: URL = {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let url = URL(string: urlString)
        else {
            fatalError("Missing or invalid SUPABASE_URL in Info.plist")
        }
        return url
    }()

    /// The public anonymous key for Supabase.
    static let anonKey: String = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String else {
            fatalError("Missing SUPABASE_ANON_KEY in Info.plist")
        }
        return key
    }()
}

