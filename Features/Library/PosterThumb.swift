import SwiftUI

struct PosterThumb: View {
    let posterPath: String?
    let title: String
    var width: CGFloat = 60

    private var height: CGFloat { width * 1.5 }

    var body: some View {
        ZStack {
            if let url = makeURL(from: posterPath) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel(Text(title))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
            Image(systemName: "film")
                .imageScale(.medium)
                .foregroundStyle(.secondary)
        }
    }

    private func makeURL(from path: String?) -> URL? {
        guard let p = path, !p.isEmpty else { return nil }
        if p.hasPrefix("http://") || p.hasPrefix("https://") {
            return URL(string: p)
        }
        return URL(string: "https://image.tmdb.org/t/p/w342\(p)")
    }
}
