import Foundation

enum SupabaseConfig {
    static var urlString: String { value(for: "SUPABASE_URL") }
    static var anonKey: String { value(for: "SUPABASE_ANON_KEY") }

    static var url: URL {
        guard let u = URL(string: urlString) else {
            fatalError("Invalid SUPABASE_URL in Info.plist: \(urlString)")
        }
        return u
    }

    private static func value(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            fatalError("Missing \(key) in Info.plist")
        }
        return value
    }
}
