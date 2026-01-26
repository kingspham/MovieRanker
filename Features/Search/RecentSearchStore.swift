import Foundation
import Combine   // Required for ObservableObject / @Published

@MainActor
final class RecentSearchStore: ObservableObject {
    private static let cap = 12

    @Published private(set) var recent: [String]
    private let key = "recent.searches"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.recent = userDefaults.stringArray(forKey: key) ?? []
    }

    func add(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }

        var arr = recent
        arr.removeAll { $0.compare(t, options: .caseInsensitive) == .orderedSame }
        arr.insert(t, at: 0)

        if arr.count > Self.cap {
            arr.removeLast(arr.count - Self.cap)
        }

        recent = arr
        userDefaults.set(arr, forKey: key)
    }

    func clear() {
        recent = []
        userDefaults.set([], forKey: key)
    }
}
