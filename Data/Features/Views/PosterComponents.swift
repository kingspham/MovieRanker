import SwiftUI

// Import TMDbClient for image URL generation
// Note: TMDbClient is defined in TMDbAPI.swift

/// Small TMDb poster thumbnail (default 60x90).
struct PosterThumb: View {
    let posterPath: String?
    let title: String
    var width: CGFloat = 60

    var body: some View {
        let height = width * 1.5
        ZStack {
            if let url = TMDbClient.makeImageURL(path: posterPath, size: .w185) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty: thumbPlaceholder.redacted(reason: .placeholder)
                    case .success(let img): img.resizable().scaledToFill()
                    case .failure: thumbPlaceholder
                    @unknown default: thumbPlaceholder
                    }
                }
            } else {
                thumbPlaceholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .accessibilityLabel(Text(title))
    }

    private var thumbPlaceholder: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.12))
            Image(systemName: "film")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
    }
}

/// Larger poster component (uses TMDb w342). Frame it from the parent.
struct Poster: View {
    let posterPath: String?
    let title: String
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            if let url = TMDbClient.makeImageURL(path: posterPath, size: .w342) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty: posterPlaceholder.redacted(reason: .placeholder)
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: posterPlaceholder
                    @unknown default: posterPlaceholder
                    }
                }
            } else {
                posterPlaceholder
            }
        }
        .aspectRatio(2.0/3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .accessibilityLabel(Text(title))
    }

    private var posterPlaceholder: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.12))
            VStack(spacing: 6) {
                Image(systemName: "film")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.secondary)
                Text(shortTitle(title))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 6)
            }
            .padding(8)
        }
    }

    private func shortTitle(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 24 { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 24)
        return String(trimmed[..<idx]) + "…"
    }
}
