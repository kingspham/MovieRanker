import SwiftUI

struct ReviewRow: View {
    let review: UserReview
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    var onShare: (() -> Void)?

    @ObservedObject private var svc = ReviewService.shared
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Body with “Read more”
            Group {
                if review.body.count > 220 && !expanded {
                    Text(review.body.prefix(220) + "…")
                } else {
                    Text(review.body)
                }
            }
            .accessibilityLabel("Review text")

            // Meta row
            HStack(spacing: 14) {
                Button {
                    Task { await svc.toggleLike(reviewID: review.id) }
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                } label: {
                    let liked = svc.likedByMe.contains(review.id)
                    HStack(spacing: 6) {
                        Image(systemName: liked ? "heart.fill" : "heart")
                        Text("\(svc.likeCounts[review.id, default: 0])")
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Like review")

                Button {
                    expanded.toggle()
                } label: {
                    Text(expanded ? "Less" : "Read more")
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(review.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Edit", systemImage: "square.and.pencil") { onEdit?() }
            Button("Share", systemImage: "square.and.arrow.up") { onShare?() }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete?() }
        }
        .task(id: review.id) {
            await ReviewService.shared.refreshLikes(for: [review.id])
        }
    }
}
