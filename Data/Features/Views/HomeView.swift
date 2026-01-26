//
//  HomeView.swift
//  MovieRanker
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context

    // Region & providers
    @State private var region: String = "US"
    // Netflix=8, Prime=119, Disney+=337, Max=384, Hulu=15, Apple TV+=350
    @State private var providerIDs: [Int] = [8, 119, 337, 384, 15, 350]

    @State private var nowPlaying: [TMDbMovie] = []
    @State private var upcoming:   [TMDbMovie] = []
    @State private var streaming:  [TMDbMovie] = []
    @State private var loading = false
    @State private var errorText: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    VStack(spacing: 16) {
                        ProgressView("Loading today's highlights…")
                        Text("Fetching new releases from TMDb…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = errorText {
                    ContentUnavailableView(
                        "Couldn't load",
                        systemImage: "exclamationmark.triangle",
                        description: Text(err)
                    )
                } else {
                    List {
                        if !nowPlaying.isEmpty {
                            Section(header: Text("🎬 In Theaters Now")) {
                                ForEach(nowPlaying, id: \.id) { m in
                                    NavigationLink {
                                        MovieInfoView(tmdb: m).modelContext(context)
                                    } label: {
                                        MovieRow(movie: m, rightBadge: "In Theaters")
                                    }
                                }
                            }
                        }

                        if !upcoming.isEmpty {
                            Section(header: Text("🔜 Coming to Theaters")) {
                                ForEach(upcoming, id: \.id) { m in
                                    NavigationLink {
                                        MovieInfoView(tmdb: m).modelContext(context)
                                    } label: {
                                        MovieRow(
                                            movie: m,
                                            subtitleOverride: m.year.map(String.init),
                                            rightBadge: "Upcoming"
                                        )
                                    }
                                }
                            }
                        }

                        if !streaming.isEmpty {
                            Section(header: Text("📺 On Streaming")) {
                                ForEach(streaming, id: \.id) { m in
                                    NavigationLink {
                                        MovieInfoView(tmdb: m).modelContext(context)
                                    } label: {
                                        MovieRow(movie: m, rightBadge: "Streaming")
                                    }
                                }
                            }
                        }
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #else
                    .listStyle(.inset)
                    #endif
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Region", selection: $region) {
                            Text("US").tag("US")
                            Text("UK").tag("GB")
                            Text("Canada").tag("CA")
                            Text("Australia").tag("AU")
                        }
                        .onChange(of: region) { _, _ in Task { await refresh() } }

                        Section("Streaming Providers") {
                            ProviderToggle(id: 8,   name: "Netflix",   selection: $providerIDs)
                            ProviderToggle(id: 119, name: "Prime",     selection: $providerIDs)
                            ProviderToggle(id: 337, name: "Disney+",   selection: $providerIDs)
                            ProviderToggle(id: 384, name: "Max",       selection: $providerIDs)
                            ProviderToggle(id: 15,  name: "Hulu",      selection: $providerIDs)
                            ProviderToggle(id: 350, name: "Apple TV+", selection: $providerIDs)
                        }

                        Button("Reload") { Task { await refresh() } }
                    } label: { Image(systemName: "slider.horizontal.3") }
                }
            }
            .task { await refresh() }
        }
    }

    // MARK: - Data

    private func refresh() async {
        loading = true
        errorText = nil
        
        do {
            async let a = TMDbClient.shared.nowPlaying(region: region)
            async let b = TMDbClient.shared.upcoming(region: region)
            async let c = TMDbClient.shared.streamingNow(providers: providerIDs, region: region)

            let (np, up, st) = try await (a, b, c)

            nowPlaying = Array(np.results.prefix(12))
            upcoming   = Array(up.results.prefix(12))
            streaming  = Array(st.results.prefix(12))
        } catch {
            errorText = error.localizedDescription
            nowPlaying = []
            upcoming = []
            streaming = []
        }
        
        loading = false
    }
}

// MARK: - Rows & Helpers

private struct MovieRow: View {
    let movie: TMDbMovie
    var subtitleOverride: String? = nil
    var rightBadge: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            PosterThumb(posterPath: movie.posterPath, title: movie.title, width: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(movie.title).font(.headline)
                if let s = subtitleOverride ?? movie.year.map(String.init) {
                    Text(s).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let b = rightBadge {
                Text(b)
                    .font(.caption).bold()
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProviderToggle: View {
    let id: Int
    let name: String
    @Binding var selection: [Int]

    var body: some View {
        let isOn = selection.contains(id)
        Button {
            if isOn { selection.removeAll { $0 == id } }
            else    { selection.append(id) }
        } label: {
            Label(name, systemImage: isOn ? "checkmark.circle.fill" : "circle")
        }
    }
}
