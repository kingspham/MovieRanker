//
//  YourListView.swift
//  MovieRanker
//

import SwiftUI
import SwiftData

struct YourListView: View {
    @Environment(\.modelContext) private var context

    private let userId: String
    @Query private var items: [UserItem]

    @State private var tab: Tab = .watchlist

    enum Tab: String, CaseIterable, Identifiable {
        case watchlist = "Want to Watch"
        case seen      = "Watched"
        var id: String { rawValue }
    }

    init() {
        let uid = SessionManager.shared.userId ?? "guest"
        self.userId = uid
        _items = Query(filter: #Predicate<UserItem> { $0.ownerId == uid })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                let listData = filteredItems

                if listData.isEmpty {
                    ContentUnavailableView(
                        tab == .watchlist ? "Nothing saved yet" : "Nothing watched yet",
                        systemImage: tab == .watchlist ? "bookmark" : "checkmark.circle",
                        description: Text(tab == .watchlist
                                          ? "Search a movie or show and tap “Want to Watch”."
                                          : "Mark something as watched from its page.")
                    )
                    .padding()
                } else {
                    List {
                        ForEach(listData, id: \.persistentModelID) { it in
                            ItemRow(item: it, userId: userId) {
                                SD.save(context)
                            } onDelete: {
                                context.delete(it)
                                SD.save(context)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Your List")
        }
    }

    private var filteredItems: [UserItem] {
        let target: UserItem.State = (tab == .watchlist) ? .watchlist : .seen
        return items.filter { $0.state == target }
    }
}

// MARK: - Row

private struct ItemRow: View {
    @Environment(\.modelContext) private var context

    let item: UserItem
    let userId: String
    var onStateChanged: () -> Void
    var onDelete: () -> Void

    var body: some View {
        NavigationLink { destinationView } label: {
            HStack(spacing: 12) {
                if let m = item.movie {
                    PosterThumb(posterPath: m.posterPath, title: m.title, width: 48)
                } else if let s = item.show {
                    PosterThumb(posterPath: s.posterPath, title: s.title, width: 48)
                } else {
                    PosterThumb(posterPath: nil, title: "Unknown", width: 48)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryTitle).font(.headline)
                    if let sub = subtitle { Text(sub).foregroundStyle(.secondary) }
                }
                Spacer()

                Capsule()
                    .fill(item.state == .seen ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                    .overlay(
                        Text(item.state == .seen ? "Watched" : "Want to Watch")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    )
                    .frame(height: 24)
            }
            .padding(.vertical, 4)
        }
        .swipeActions(edge: .trailing) {
            if item.state == .watchlist {
                Button {
                    setState(.seen)
                } label: { Label("Mark Watched", systemImage: "checkmark.circle") }
                .tint(.green)
            } else {
                Button {
                    setState(.watchlist)
                } label: { Label("Want to Watch", systemImage: "bookmark") }
                .tint(.blue)
            }

            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var primaryTitle: String {
        item.movie?.title ?? item.show?.title ?? "Unknown"
    }

    private var subtitle: String? {
        if let y = item.movie?.year { return String(y) }
        if let y = item.show?.yearStart { return String(y) }
        return nil
    }

    // MARK: - Destinations

    @ViewBuilder
    private var destinationView: some View {
        if let m = item.movie, let tmdbId = m.tmdbID {
            MovieInfoView(tmdb: TMDbMovie(
                id: tmdbId,
                title: m.title,
                overview: nil,
                releaseDate: m.year.flatMap { String($0) },
                posterPath: m.posterPath
            ))
        } else if let s = item.show, let tmdbId = s.tmdbID {
            ShowInfoView(tmdb: TMDbShow(
                id: tmdbId,
                title: s.title,
                overview: nil,
                firstAirDate: s.yearStart.map { "\($0)-01-01" },
                posterPath: s.posterPath,
                genreIDs: s.genreIDs ?? [],
                popularity: s.popularity
            ))
        } else if let m = item.movie {
            SimpleStoredMovieView(movie: m)
        } else if let s = item.show {
            SimpleStoredShowView(show: s)
        } else {
            Text("Item not found.")
        }
    }

    // MARK: - State change

    private func setState(_ st: UserItem.State) {
        item.state = st
        onStateChanged()
    }
}

// MARK: - Simple fallbacks (no TMDb id)

private struct SimpleStoredMovieView: View {
    let movie: Movie
    var body: some View {
        List {
            HStack(spacing: 12) {
                PosterThumb(posterPath: movie.posterPath, title: movie.title, width: 64)
                VStack(alignment: .leading) {
                    Text(movie.title).font(.title3).bold()
                    if let y = movie.year { Text(String(y)).foregroundStyle(.secondary) }
                }
            }
            if !movie.genreIDs.isEmpty {
                let gen = movie.genreIDs
                Text("Genres: \(gen.map(String.init).joined(separator: ", "))")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(movie.title)
    }
}

private struct SimpleStoredShowView: View {
    let show: Show
    var body: some View {
        List {
            HStack(spacing: 12) {
                PosterThumb(posterPath: show.posterPath, title: show.title, width: 64)
                VStack(alignment: .leading) {
                    Text(show.title).font(.title3).bold()
                    if let y = show.yearStart { Text(String(y)).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle(show.title)
    }
}

