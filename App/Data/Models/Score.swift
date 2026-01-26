import Foundation
import SwiftData

@Model
final class Score {
    @Attribute(.unique) var id: UUID
    var movieID: UUID
    var display100: Int   // 0–100 for UI
    var latent: Double    // your underlying rating signal
    var variance: Double
    var ownerId: String

    init(movieID: UUID, display100: Int, latent: Double, variance: Double, ownerId: String) {
        self.id = UUID()
        self.movieID = movieID
        self.display100 = display100
        self.latent = latent
        self.variance = variance
        self.ownerId = ownerId
    }
}
