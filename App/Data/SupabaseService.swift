import Foundation
import Combine

public struct AppSupabaseConfig {
    public let url: URL
    public let anonKey: String
    public init(url: URL, anonKey: String) {
        self.url = url
        self.anonKey = anonKey
    }
}

final class AppServices: ObservableObject {
    let config: AppSupabaseConfig

    init() {
        // Initialize from Info.plist via SupabaseConfig
        self.config = AppSupabaseConfig(
            url: SupabaseConfig.url,
            anonKey: SupabaseConfig.anonKey
        )
    }
}
