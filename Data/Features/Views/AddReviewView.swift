import SwiftUI
import SwiftData

struct AddReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let movie: Movie
    var onSaved: (() -> Void)?

    @State private var text: String = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Review for")
                    .font(.caption).foregroundStyle(.secondary)
                Text(movie.title).font(.headline)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
                    if text.isEmpty {
                        Text("Share a quick thought…")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }

                HStack {
                    Spacer()
                    Text("\(text.count)/1000")
                        .font(.caption)
                        .foregroundStyle(text.count > 1000 ? .red : .secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Add Review")
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") { hideKeyboard() }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(text.trimmed().isEmpty || text.count > 1000 || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        let owner = SessionManager.shared.userId
        let review = UserReview(body: text.trimmed(), ownerId: SessionManager.shared.userId)
        review.rating = 0
        review.movie = movie
        review.ownerId = owner
        context.insert(review)
        do { try context.save() } catch { print("Review save error:", error.localizedDescription) }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        onSaved?()
        dismiss()
    }

    private func hideKeyboard() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

private extension String {
    func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
