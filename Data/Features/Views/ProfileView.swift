import SwiftUI
import SwiftData

@MainActor
struct ProfileView: View {
    @Environment(\.modelContext) private var context

    @State private var totalMovies: Int = 0
    @State private var totalLogs: Int = 0

    var body: some View {
        List {
            Section("Your Stats") {
                LabeledContent("Movies in Library", value: "\(totalMovies)")
                LabeledContent("Watch Logs", value: "\(totalLogs)")
            }
        }
        .navigationTitle("Profile")
        .task { await refresh() }
    }

    private func refresh() async {
        let movies: Int = (try? context.fetchCount(FetchDescriptor<Movie>())) ?? 0
        let logs: Int = (try? context.fetchCount(FetchDescriptor<LogEntry>())) ?? 0
        totalMovies = movies
        totalLogs = logs
    }
}
