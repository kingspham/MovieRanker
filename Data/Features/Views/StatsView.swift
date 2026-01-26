//
//  StatsView.swift
//  MovieRanker
//

import SwiftUI
import SwiftData

/// Personal stats screen powered by StatsViewModel.
/// Shows top-line metrics, recent ratings, and genre breakdown.
struct StatsView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var vm = StatsViewModel()

    var body: some View {
        List {
            overviewSection

            if !vm.recentRatings.isEmpty {
                Section(header: Text("Recent Ratings")) {
                    ForEach(vm.recentRatings, id: \.date) { item in
                        HStack {
                            Text(dateString(item.date))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Meter(value: item.rating / 100.0)
                                .frame(width: 140, height: 10)
                            Text("\(Int(item.rating))")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(dateString(item.date)), rating \(Int(item.rating))")
                    }
                }
            } else {
                Section("Recent Ratings") {
                    Text("No ratings yet")
                        .foregroundStyle(.secondary)
                }
            }

            Section(header: Text("Top Genres")) {
                if vm.topGenres.isEmpty {
                    Text("No genre data yet")
                        .foregroundStyle(.secondary)
                } else {
                    FlowWrap(vm.topGenres) { g in
                        Chip(text: g)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
#if os(macOS)
        .listStyle(.inset)
#else
        .listStyle(.insetGrouped)
#endif
        .navigationTitle("Your Stats")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    vm.load(from: context)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .task {
            vm.load(from: context)
        }
    }

    // MARK: - Sections

    private var overviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(vm.headerSummary)
                    .font(.headline)

                HStack(spacing: 12) {
                    StatCard(title: "Watched", value: "\(vm.totalWatched)", symbol: "checkmark.circle.fill")
                    StatCard(title: "Want to Watch", value: "\(vm.totalWatchlist)", symbol: "bookmark.fill")
                }

                HStack(spacing: 12) {
                    StatCard(title: "Avg Rating", value: "\(Int(round(vm.avgRating)))", symbol: "star.fill")
                    StatCard(title: "Avg Rank", value: "\(Int(round(vm.avgElo)))", symbol: "trophy.fill")
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Formatting

    private func dateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }
}

// MARK: - Small UI helpers (private)

private struct StatCard: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .imageScale(.large)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline).monospacedDigit()
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption).bold()
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct Meter: View {
    let value: Double // 0…1
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor.opacity(0.9))
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
    }
}

/// Simple flow layout for chips (horizontal wrap).
private struct FlowWrap<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let content: (Data.Element) -> Content

    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }

    @State private var totalHeight: CGFloat = .zero

    var body: some View {
        VStack {
            GeometryReader { geo in
                self.generateContent(in: geo)
            }
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in geo: GeometryProxy) -> some View {
        var x: CGFloat = 0
        var y: CGFloat = 0

        return ZStack(alignment: .topLeading) {
            ForEach(Array(data), id: \.self) { element in
                content(element)
                    .padding(.trailing, 6)
                    .alignmentGuide(.leading) { _ in
                        if (x + 120) > geo.size.width { // naive width cap
                            x = 0
                            y -= 28
                        }
                        let result = x
                        x += 120
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = y
                        return result
                    }
            }
        }
        .background(
            GeometryReader { innerGeo in
                Color.clear
                    .onAppear { totalHeight = -y + 28 }
                    .onChange(of: geo.size) { _, _ in totalHeight = -y + 28 }
                    .onChange(of: data.count) { _, _ in totalHeight = -y + 28 }
            }
        )
    }
}
