import SwiftUI

struct UserListView: View {
    let title: String
    let userIDs: [SocialProfile] // We pass the loaded profiles directly
    
    var body: some View {
        List(userIDs) { user in
            NavigationLink(destination: PublicProfileView(profile: user)) {
                HStack {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(Text(String(user.displayName.prefix(1))).bold())
                    
                    VStack(alignment: .leading) {
                        Text(user.username ?? "User").font(.headline)
                        if let name = user.fullName {
                            Text(name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}
