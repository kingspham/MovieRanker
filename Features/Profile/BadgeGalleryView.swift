import SwiftUI
import SwiftData

struct BadgeGalleryView: View {
    @Environment(\.modelContext) private var context
    @Query private var allLogs: [LogEntry]
    @StateObject private var badgeService = BadgeService.shared
    
    // Grid Layout
    let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 20)
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                
                // HEADER STATS
                VStack(spacing: 8) {
                    Text("\(badgeService.badges.filter { $0.isUnlocked }.count) / \(badgeService.badges.count)")
                        .font(.system(size: 48, weight: .black))
                        .foregroundStyle(Color.accentColor)
                    
                    Text("BADGES UNLOCKED")
                        .font(.caption).bold().tracking(2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top)
                
                // SECTIONS
                BadgeSection(title: "Milestones", filter: "m_")
                BadgeSection(title: "Streaks", filter: "s_")
                BadgeSection(title: "Holidays", filter: "h_")
                BadgeSection(title: "Genres", filter: "g_")
                BadgeSection(title: "Decades", filter: "dec_")
            }
            .padding()
        }
        .navigationTitle("Trophy Case")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard badgeService.badges.isEmpty else { return }
            let userId = AuthService.shared.currentUserId() ?? "guest"
            let inputs = allLogs
                .filter { $0.ownerId == userId }
                .compactMap { log -> BadgeInput? in
                    guard let movie = log.movie else { return nil }
                    return BadgeInput(watchedOn: log.watchedOn, genreIDs: movie.genreIDs)
                }
            badgeService.calculateBadges(inputs: inputs)
        }
    }
    
    func BadgeSection(title: String, filter: String) -> some View {
        let sectionBadges = badgeService.badges.filter { $0.id.starts(with: filter) }
        
        return VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3).bold()
            
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(sectionBadges, id: \.id) { badge in
                    Button {
                        // Tap to see details (optional, could show alert)
                    } label: {
                        VStack(spacing: 8) {
                            PremiumBadgeView(badge: badge)
                            
                            if !badge.isUnlocked {
                                Text(badge.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(height: 30)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
