import SwiftUI
import SwiftData

struct EditReviewView: View {
    @Bindable var review: UserReview
    var onDone: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            Form {
                Section("Review") {
                    TextEditor(text: $review.body)
                        .frame(minHeight: 160)
                        .font(.body)
                        .submitLabel(.done)
                }
            }
            .navigationTitle("Edit Review")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        review.updatedAt = Date()
                        SD.save(context)
                        onDone()
                        dismiss()
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    // In-memory SwiftData container just for preview
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container: ModelContainer = try! ModelContainer(for: UserReview.self, configurations: config)

    let sample = UserReview(body: "Quick thoughts on the show…", ownerId: nil)
    container.mainContext.insert(sample)

    return EditReviewView(review: sample)
        .modelContainer(container)
}
#endif

