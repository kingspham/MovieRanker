import SwiftUI

struct FlexListView: View {
    let title: String
    let items: [FlexItem]
    let username: String
    
    struct FlexItem: Identifiable {
        let id = UUID()
        let rank: Int
        let title: String
        let posterPath: String?
        let score: Int
    }
    
    var body: some View {
        ZStack {
            // Dark Background
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                // Branding Header
                HStack {
                    Image(systemName: "film.stack.fill")
                        .foregroundStyle(.yellow)
                    Text("MovieRanker")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Text(username)
                        .font(.subheadline)
                        .bold()
                        .foregroundStyle(.gray)
                }
                .padding(.horizontal)
                .padding(.top, 40)
                
                // List Title
                Text(title)
                    .font(.system(size: 32, weight: .black))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .multilineTextAlignment(.center)
                
                // The List Rows
                VStack(spacing: 12) {
                    ForEach(items.prefix(10)) { item in
                        HStack(spacing: 12) {
                            Text("#\(item.rank)")
                                .font(.title3).fontWeight(.heavy)
                                .foregroundStyle(.white)
                                .frame(width: 40, alignment: .leading)
                            
                            if let path = item.posterPath {
                                AsyncImage(url: TMDbClient.makeImageURL(path: path, size: .w185)) { p in
                                    if let i = p.image { i.resizable().scaledToFill() } else { Color.gray.opacity(0.3) }
                                }
                                .frame(width: 30, height: 45).cornerRadius(4)
                            }
                            
                            Text(item.title)
                                .font(.headline).foregroundStyle(.white)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text("\(item.score)")
                                .font(.subheadline).fontWeight(.bold)
                                .foregroundStyle(item.score >= 90 ? .green : (item.score >= 70 ? .blue : .orange))
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                Spacer()
            }
            .padding(24)
        }
        .frame(width: 390, height: 800) // Standard Mobile Ratio for Sharing
    }
}
