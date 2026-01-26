// PersonDetailView.swift
import SwiftUI
import SwiftData

struct PersonDetailView: View {
    let personId: Int
    let personName: String
    
    @Environment(\.modelContext) private var context
    
    // STATE
    @State private var biography: String = ""
    @State private var birthday: String = ""
    @State private var placeOfBirth: String = ""
    @State private var profilePath: String?
    @State private var knownFor: [TMDbItem] = []
    @State private var isLoading = true
    
    // SAFE DATA
    @State private var seenTMDBIds: Set<Int> = []
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // 1. HEADER (Image + Bio)
                HStack(alignment: .top, spacing: 16) {
                    if let path = profilePath {
                        AsyncImage(url: TMDbClient.makeImageURL(path: path, size: .w500)) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Color.gray.opacity(0.3)
                            }
                        }
                        .frame(width: 120, height: 180)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                    } else {
                        Rectangle().fill(Color.gray.opacity(0.3))
                            .frame(width: 120, height: 180)
                            .cornerRadius(12)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(personName)
                            .font(.title2).fontWeight(.bold)
                        
                        if !birthday.isEmpty {
                            Text("Born: \(birthday)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        
                        if !placeOfBirth.isEmpty {
                            Text(placeOfBirth)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        
                        // SEEN COUNT
                        let seenCount = knownFor.filter { seenTMDBIds.contains($0.id) }.count
                        if seenCount > 0 {
                            Text("Seen \(seenCount) of \(knownFor.count)")                                .font(.caption).bold()
                                .padding(6)
                                .background(Color.green.opacity(0.1))
                                .foregroundColor(.green)
                                .cornerRadius(6)
                        }
                    }
                }
                .padding(.horizontal)
                
                // 2. BIOGRAPHY
                if !biography.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Biography").font(.headline)
                        Text(biography)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(isLoading ? 3 : nil) // Expand fully
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal)
                }
                
                // 3. KNOWN FOR (Filmography)
                if !knownFor.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Filmography").font(.headline).padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(knownFor) { movie in
                                    NavigationLink {
                                        MovieInfoView(tmdb: movie, mediaType: movie.mediaType ?? "movie")
                                    } label: {
                                        VStack(alignment: .leading) {
                                            ZStack(alignment: .topTrailing) {
                                                PosterThumb(posterPath: movie.posterPath, title: movie.displayTitle, width: 100)
                                                
                                                if seenTMDBIds.contains(movie.id) {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(.green)
                                                        .background(Circle().fill(.white))
                                                        .padding(4)
                                                }
                                            }
                                            
                                            Text(movie.displayTitle)
                                                .font(.caption).bold()
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                                .foregroundStyle(.primary)
                                                .frame(width: 100, alignment: .leading)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                Spacer(minLength: 50)
            }
            .padding(.top)
        }
        .navigationTitle(personName)
        // FIX: Only modify navbar on iOS
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadPersonDetails()
        }
    }
    
    // MARK: - Safe Data Loading
    private func loadPersonDetails() async {
        guard let client = try? TMDbClient() else { return }
        
        // 1. Fetch Person Data
        if let details = try? await client.getPersonDetails(id: personId) {
            self.biography = details.biography ?? ""
            self.birthday = details.birthday ?? ""
            self.placeOfBirth = details.placeOfBirth ?? ""
            self.profilePath = details.profilePath
        }
        
        // 2. Fetch Credits
        if let credits = try? await client.getPersonCredits(id: personId) {
            let sorted = credits.cast.sorted { (a: TMDbItem, b: TMDbItem) -> Bool in
                (a.popularity ?? 0) > (b.popularity ?? 0)
            }
            var uniqueItems: [TMDbItem] = []
            var seenIds = Set<Int>()
            for item in sorted {
                if !seenIds.contains(item.id) {
                    uniqueItems.append(item)
                    seenIds.insert(item.id)
                }
            }
            self.knownFor = uniqueItems
        }
        
        // 3. Check Seen Status
        await MainActor.run {
            let allItems = (try? context.fetch(FetchDescriptor<UserItem>())) ?? []
            let seenItems = allItems.filter { $0.state == .seen }
            self.seenTMDBIds = Set(seenItems.compactMap { $0.movie?.tmdbID })
            self.isLoading = false
        }
    }
}
