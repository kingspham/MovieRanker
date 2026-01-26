import SwiftUI

struct SearchResultRow: View {
    let title: String
    let subtitle: String?
    let posterPath: String?

    var body: some View {
        HStack(spacing: 12) {
            PosterThumb(posterPath: posterPath, title: title, width: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body).bold().lineLimit(2)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
    }
}
