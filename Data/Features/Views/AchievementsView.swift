//
//  AchievementsView.swift
//  MovieRanker
//

import SwiftUI
import SwiftData

struct AchievementsView: View {
    @Environment(\.modelContext) private var context
    @State private var rows: [BadgeProgress] = []
    @State private var isLoading = false

    var body: some View {
        List {
            if isLoading {
                ProgressView("Checking your achievements…")
            } else if rows.isEmpty {
                ContentUnavailableView("No achievements yet",
                                       systemImage: "medal.fill",
                                       description: Text("Log and rank to start earning badges."))
            } else {
                Section {
                    ForEach(rows) { b in
                        AchievementRow(progress: b)
                    }
                }
            }
        }
#if os(iOS)
        .listStyle(.insetGrouped)
#else
        .listStyle(.inset)
#endif
        .navigationTitle("Achievements")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .task { refresh() }
    }

    private func refresh() {
        isLoading = true
        rows = AchievementsEngine.computeProgress(context: context)
        isLoading = false
    }
}

private struct AchievementRow: View {
    let progress: BadgeProgress

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(progress.earned ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                    .frame(width: 46, height: 46)
                Image(systemName: progress.systemImage)
                    .imageScale(.large)
                    .foregroundStyle(progress.earned ? Color.accentColor : .secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(progress.title)
                        .font(.headline)
                    if progress.earned, let date = progress.earnedAt {
                        Text(dateString(date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(progress.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                HStack {
                    Text("\(min(progress.current, progress.goal)) / \(progress.goal)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if progress.earned {
                        Label("Unlocked", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func dateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }
}

