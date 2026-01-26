import SwiftUI

struct FlexCardView: View {
    let movieTitle: String
    let posterPath: String?
    let score: Int
    let rank: Int?
    let username: String
    let avatarInitial: String
    
    var body: some View {
        ZStack {
            // Background: Blurred Poster
            GeometryReader { geo in
                if let path = posterPath {
                    AsyncImage(url: TMDbClient.makeImageURL(path: path, size: .original)) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                                .blur(radius: 20)
                                .overlay(Color.black.opacity(0.6))
                        } else {
                            Color.black
                        }
                    }
                } else {
                    Color.black
                }
            }
            
            // Content
            VStack(spacing: 24) {
                // Logo
                HStack {
                    Image(systemName: "film.stack.fill")
                        .foregroundStyle(.yellow)
                    Text("MovieRanker")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                }
                
                Spacer()
                
                // Main Poster
                if let path = posterPath {
                    AsyncImage(url: TMDbClient.makeImageURL(path: path, size: .w342)) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFit()
                                .cornerRadius(16)
                                .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
                    .frame(height: 300)
                }
                
                // Title & Score
                VStack(spacing: 8) {
                    Text(movieTitle)
                        .font(.title).fontWeight(.black)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                    
                    HStack(spacing: 20) {
                        // Score Badge
                        VStack {
                            Text("\(score)")
                                .font(.system(size: 48, weight: .heavy))
                                .foregroundStyle(scoreColor(score))
                            Text("SCORE")
                                .font(.caption2).bold()
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        
                        if let r = rank {
                            Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: 40)
                            
                            VStack {
                                Text("#\(r)")
                                    .font(.system(size: 48, weight: .heavy))
                                    .foregroundStyle(.white)
                                Text("RANK")
                                    .font(.caption2).bold()
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                }
                
                Spacer()
                
                // User Footer
                HStack {
                    Circle().fill(Color.white.opacity(0.2)).frame(width: 32, height: 32)
                        .overlay(Text(avatarInitial).bold().foregroundStyle(.white))
                    
                    Text(username)
                        .font(.subheadline).bold()
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Text(Date().formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.top)
            }
            .padding(32)
        }
        .frame(width: 350, height: 600) // Instagram Story Ratio-ish
        .background(Color.black)
        .cornerRadius(24)
    }
    
    private func scoreColor(_ score: Int) -> Color {
        if score >= 90 { return .green }
        if score >= 70 { return .blue }
        if score >= 50 { return .orange }
        return .red
    }
}
