import Foundation

struct Badge: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let description: String
    let icon: String
    let color: String // hex or name
    var unlocked: Bool = false
}
