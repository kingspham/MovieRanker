import SwiftUI
import SwiftData

struct MarkWatchedShowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let show: Show
    let onDone: () -> Void

    @State private var notes: String = ""
    @State private var watchedDate = Date()
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Watched on", selection: $watchedDate, displayedComponents: .date)
                TextField("Notes (optional)", text: $notes)
            }
            .navigationTitle("Mark Watched")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { save() }.disabled(saving)
                }
            }
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        let owner = SessionManager.shared.userId ?? "unknown"
        let entry = LogEntry(
            createdAt: .now,
            rating: nil,
            watchedOn: watchedDate,
            whereWatched: nil,
            withWho: nil,
            notes: notes.isEmpty ? nil : notes,
            labels: nil,
            movie: nil,
            show: show,
            ownerId: owner
        )
        context.insert(entry)
        SD.save(context)
        saving = false
        onDone()
        dismiss()
    }
}
