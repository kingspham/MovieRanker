import SwiftUI
import SwiftData
import Combine

struct BadgeInput: Sendable {
    let watchedOn: Date?
    let genreIDs: [Int]
}

struct AppBadge: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let colorString: String
    var isUnlocked: Bool = false
    
    var color: Color {
        switch colorString {
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "blue": return .blue
        case "green": return .green
        case "pink": return .pink
        case "cyan": return .cyan
        case "black": return .black
        case "gray": return .gray
        case "brown": return .brown
        case "indigo": return .indigo
        default: return .gray
        }
    }
    
    static func == (lhs: AppBadge, rhs: AppBadge) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
class BadgeService: ObservableObject {
    static let shared = BadgeService()
    private init() {}

    @Published var badges: [AppBadge] = []
    @Published var recentBadges: [AppBadge] = []
    @Published var latestUnlock: AppBadge? = nil

    // Track previously unlocked badge IDs to detect new unlocks
    private var previouslyUnlockedIDs: Set<String> = []

    // Flag to track if this is the initial load (should NOT show popups)
    private var hasCompletedInitialLoad = false

    // Call this on app start / profile load - will NOT show popups
    func calculateBadges(inputs: [BadgeInput]) {
        calculateBadgesInternal(inputs: inputs, showPopup: hasCompletedInitialLoad)
        hasCompletedInitialLoad = true
    }

    // Call this after ranking - WILL show popup if new badge unlocked
    func recalculateAfterRanking(inputs: [BadgeInput]) {
        hasCompletedInitialLoad = true // Ensure flag is set
        calculateBadgesInternal(inputs: inputs, showPopup: true)
    }

    private func calculateBadgesInternal(inputs: [BadgeInput], showPopup: Bool) {
        // Run on background priority
        Task.detached(priority: .background) {
            let newBadges = self.performCalculation(inputs: inputs)

            await MainActor.run {
                let oldIDs = self.previouslyUnlockedIDs
                let newUnlockedIDs = Set(newBadges.filter { $0.isUnlocked }.map { $0.id })

                self.badges = newBadges
                self.recentBadges = Array(newBadges.sorted { $0.isUnlocked && !$1.isUnlocked }.prefix(8))

                // Only show popup if explicitly requested AND there's a newly unlocked badge
                if showPopup {
                    let newlyUnlocked = newBadges.filter { $0.isUnlocked && !oldIDs.contains($0.id) }
                    if let firstNew = newlyUnlocked.first {
                        self.latestUnlock = firstNew
                    }
                }

                // Update tracking set
                self.previouslyUnlockedIDs = newUnlockedIDs
            }
        }
    }
    
    // FIX: Added 'nonisolated' so it can run in the background
    nonisolated private func performCalculation(inputs: [BadgeInput]) -> [AppBadge] {
        var list: [AppBadge] = []
        let total = inputs.count
        
        // 1. MILESTONES
        let milestones = [1, 5, 10, 25, 50, 100, 250, 500]
        for m in milestones {
            list.append(createBadge(id: "m_\(m)", name: "\(m) Club", desc: "Log \(m) items", icon: "trophy.fill", color: "yellow", unlocked: total >= m))
        }
        
        // 2. STREAKS
        let streak = calculateStreak(inputs: inputs)
        let streaks = [3, 5, 10, 20]
        for s in streaks {
            list.append(createBadge(id: "s_\(s)", name: "\(s) Week Streak", desc: "Log \(s) weeks in a row", icon: "flame.fill", color: "orange", unlocked: streak >= s))
        }
        
        // 3. GENRES (Simplified)
        var gCounts: [Int: Int] = [:]
        for item in inputs { for g in item.genreIDs { gCounts[g, default: 0] += 1 } }
        
        let genres: [(Int, String, String, String)] = [
            (28, "Action", "bolt.fill", "red"),
            (12, "Adventure", "map.fill", "brown"),
            (16, "Animation", "paintbrush.fill", "orange"),
            (35, "Comedy", "face.smiling", "yellow"),
            (80, "Crime", "lock.fill", "gray"),
            (99, "Documentary", "video.fill", "blue"),
            (18, "Drama", "theatermasks.fill", "purple"),
            (14, "Fantasy", "sparkles", "indigo"),
            (27, "Horror", "moon.stars.fill", "black"),
            (878, "Sci-Fi", "star.fill", "cyan")
        ]
        
        for (gid, name, icon, col) in genres {
            let count = gCounts[gid] ?? 0
            list.append(createBadge(id: "g_\(gid)_1", name: "\(name) Fan", desc: "Watch 1", icon: icon, color: col, unlocked: count >= 1))
            list.append(createBadge(id: "g_\(gid)_10", name: "\(name) Buff", desc: "Watch 10", icon: icon, color: col, unlocked: count >= 10))
            list.append(createBadge(id: "g_\(gid)_25", name: "\(name) Expert", desc: "Watch 25", icon: icon, color: col, unlocked: count >= 25))
        }

        return list
    }
    
    // FIX: Added 'nonisolated' here too
    nonisolated private func createBadge(id: String, name: String, desc: String, icon: String, color: String, unlocked: Bool) -> AppBadge {
        AppBadge(id: id, name: name, description: desc, icon: icon, colorString: color, isUnlocked: unlocked)
    }
    
    // FIX: Added 'nonisolated' here too
    nonisolated private func calculateStreak(inputs: [BadgeInput]) -> Int {
        guard !inputs.isEmpty else { return 0 }
        let calendar = Calendar.current
        let weeks = Set(inputs.compactMap { item -> String? in
            guard let d = item.watchedOn else { return nil }
            return "\(calendar.component(.year, from: d))-\(calendar.component(.weekOfYear, from: d))"
        })
        var streak = 0; var date = Date()
        while true {
            let key = "\(calendar.component(.year, from: date))-\(calendar.component(.weekOfYear, from: date))"
            if weeks.contains(key) { streak += 1; date = calendar.date(byAdding: .weekOfYear, value: -1, to: date)! } else { break }
        }
        return streak
    }
}
