import SwiftUI
import SwiftData

struct AddShowReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let show: Show
    @State private var bodyText: String = ""
    @State private var rating: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Rating: \(rating)", value: $rating, in: 0...10)
                TextEditor(text: $bodyText).frame(minHeight: 160)
            }
            .navigationTitle("Review Show")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        let review = UserReview(body: bodyText, rating: rating, ownerId: SessionManager.shared.userId, movie: nil, show: show)
        context.insert(review)
        SD.save(context)
        dismiss()
    }
}
