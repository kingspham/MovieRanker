import Foundation
import Combine

@MainActor
final class RecentSearchStore: ObservableObject {
    static let shared = RecentSearchStore()
    
    @Published private(set) var recent: [String] = []
    
    private init() {
        if let arr = UserDefaults.standard.array(forKey: "recent.searches") as? [String] {
            recent = arr
        }
    }

    func add(_ q: String) {
        let v = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        
        // Remove any existing case-insensitive match
        recent.removeAll { $0.caseInsensitiveCompare(v) == .orderedSame }
        
        // Insert at beginning
        recent.insert(v, at: 0)
        
        // Keep only last 12
        if recent.count > 12 {
            recent.removeLast(recent.count - 12)
        }
        
        // Persist
        UserDefaults.standard.set(recent, forKey: "recent.searches")
    }

    func clear() {
        recent.removeAll()
        UserDefaults.standard.set(recent, forKey: "recent.searches")
    }
}
