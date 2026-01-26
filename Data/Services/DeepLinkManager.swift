// DeepLinkManager.swift
import Foundation

#if os(iOS)
import UIKit
#endif

struct DeepLinkManager {
    
    /// Tries to open the App. If it fails, returns a Web URL to the completion handler.
    @MainActor
    static func open(providerName: String, title: String, completion: @escaping (URL) -> Void) {
        
        let safeTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        let lowerName = providerName.lowercased().replacingOccurrences(of: " ", with: "")
        
        var appURL: URL?
        
        // 1. Map Providers to App Schemes
        switch lowerName {
        case _ where lowerName.contains("netflix"):
            appURL = URL(string: "nflx://www.netflix.com/search?q=\(safeTitle)")
            
        case _ where lowerName.contains("spotify"):
            appURL = URL(string: "spotify:search:\(safeTitle)")
            
        case _ where lowerName.contains("disney"):
            appURL = URL(string: "disneyplus://")
            
        case _ where lowerName.contains("hulu"):
            appURL = URL(string: "hulu://")
            
        case _ where lowerName.contains("max") || lowerName.contains("hbo"):
            appURL = URL(string: "max://")
            
        case _ where lowerName.contains("prime"):
            appURL = URL(string: "primevideo://")
            
        case _ where lowerName.contains("youtube"):
            appURL = URL(string: "youtube://www.youtube.com/results?search_query=\(safeTitle)")
            
        case _ where lowerName.contains("apple"):
            appURL = URL(string: "videos://")
            
        default:
            appURL = nil
        }
        
        // 2. Prepare Web Fallback
        let webQuery = "watch \(title) on \(providerName)".replacingOccurrences(of: " ", with: "+")
        let webURL = URL(string: "https://www.google.com/search?q=\(webQuery)")!
        
        // 3. Attempt to Open App
        if let url = appURL {
            #if os(iOS)
            // --- iOS LOGIC ---
            UIApplication.shared.open(url, options: [:]) { success in
                if !success {
                    // App not installed or failed -> Use Web Fallback
                    completion(webURL)
                }
            }
            #else
            // --- macOS / Other Fallback ---
            // On computer, just use the web link to be safe
            completion(webURL)
            #endif
        } else {
            // Unknown provider -> Use Web Fallback
            completion(webURL)
        }
    }
}
