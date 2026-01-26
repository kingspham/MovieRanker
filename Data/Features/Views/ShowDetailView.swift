import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct ShowDetailView: View {
    @Environment(\.modelContext) private var context
    let show: Show

    // Pull everything, then filter in-memory for maximum compiler stability.
    // (With typical app data sizes this is perfectly fine and avoids Predicate issues.)
    @Query(sort: \UserReview.createdAt, order: .reverse) private var allReviews: [UserReview]
    @Query private var allItems: [UserItem]

    // UI state
    @State private var newReview: UserReview? = nil
    @State private var editingReview: UserReview? = nil

    // Derived, in-memory filters (robust and readable)
    private var reviews: [UserReview] {
        allReviews.filter { $0.show === show }
    }
    private var watchItem: UserItem? {
        allItems.first { $0.show === show }
    }

    var body: some View {
        List {
            header

            Section("Watch State") {
                HStack {
                    Text("State")
                    Spacer()
                    Menu(watchItem?.state == .seen ? "Seen" : "Watchlist") {
                        Button("Watchlist") { setState(.watchlist) }
                        Button("Seen") { setState(.seen) }
                    }
                }
            }

            Section {
                if reviews.isEmpty {
                    emptyReviewsRow
                } else {
                    ForEach(reviews) { r in
                        ReviewRow(
                            review: r,
                            onEdit: { editingReview = r },
                            onDelete: { deleteReview(r) },
                            onShare: { share(text: r.body) }
                        )
                        .swipeActions {
                            Button(role: .destructive) { deleteReview(r) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { editingReview = r } label: {
                                Label("Edit", systemImage: "square.and.pencil")
                            }
                        }
                    }

                    Button {
                        createNewReview()
                    } label: {
                        Label("Add a review", systemImage: "square.and.pencil")
                    }
                }
            } header: {
                Text("Reviews")
            }
        }
        .navigationTitle(show.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // New review sheet
        .sheet(item: $newReview) { rev in
            EditReviewView(review: rev) { }
        }
        // Edit review sheet
        .sheet(item: $editingReview) { rev in
            EditReviewView(review: rev) { }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Poster(posterPath: show.posterPath, title: show.title)
                    .frame(width: 90, height: 135)
                VStack(alignment: .leading, spacing: 4) {
                    Text(show.title)
                        .font(.title3).bold()
                    if let y = show.yearStart {
                        Text(y.formatted())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private var emptyReviewsRow: some View {
        HStack {
            Text("No reviews yet. Be the first!")
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                createNewReview()
            } label: {
                Label("Add", systemImage: "square.and.pencil")
                    .labelStyle(.iconOnly)
            }
        }
    }

    // MARK: - Watch state

    private func setState(_ st: WatchState) {
        if let it = watchItem {
            it.state = st
        } else {
            let item = UserItem(
                movie: nil,
                show: show,
                state: st,
                ownerId: SessionManager.shared.userId
            )
            context.insert(item)
        }
        SD.save(context)
    }

    // MARK: - Reviews

    private func createNewReview() {
        let r = UserReview()
        r.show = show
        r.createdAt = Date()
        context.insert(r)
        newReview = r
        SD.save(context)
    }

    private func deleteReview(_ r: UserReview) {
        context.delete(r)
        SD.save(context)
    }

    // MARK: - Share (iOS only safely)

    private func share(text: String) {
        #if os(iOS)
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(av, animated: true)
        }
        #endif
    }
}
