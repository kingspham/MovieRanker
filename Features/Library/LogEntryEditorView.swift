import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

/// Editor for creating OR editing a LogEntry tied to a Movie.
/// If `existing` is nil we create a new entry on Save.
struct LogEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let movie: Movie
    var existing: LogEntry? = nil
    var onSaved: (() -> Void)? = nil
    var onDeleted: (() -> Void)? = nil

    // Smart defaults
    @AppStorage("last_where_watched") private var lastWhereRaw: String = WatchLocation.other.rawValue
    @AppStorage("last_with_who")      private var lastWithWhoStored: String = ""
    @AppStorage("last_labels")        private var lastLabelsCSV: String = ""

    // Form state
    @State private var watchedOn: Date = Date()
    @State private var whereWatched: WatchLocation = .other
    @State private var withWho: String = ""
    @State private var notes: String = ""
    @State private var selectedLabels: Set<String> = []

    private let labelOptions = ["Emotional", "Mind-bending", "Cozy", "Action", "Slow burn"]

    var body: some View {
        NavigationStack {
            Form {
                Section(existing == nil ? "New Watch" : "Edit Watch") {
                    DatePicker("Watched on", selection: $watchedOn, displayedComponents: .date)

                    Picker("Where", selection: $whereWatched) {
                        ForEach(WatchLocation.allCases, id: \.self) { loc in
                            Text(loc.rawValue.capitalized).tag(loc)
                        }
                    }

                    TextField("With who (optional)", text: $withWho)
                }

                Section("Notes") {
                    TextEditor(text: $notes).frame(minHeight: 120)
                }

                Section("Labels") {
                    LabelsWrap(all: labelOptions, selected: $selectedLabels)
                        .padding(.vertical, 4)
                }

                Section {
                    Button(existing == nil ? "Save" : "Save Changes") { save() }
                        .buttonStyle(.borderedProminent)

                    if existing != nil {
                        Button("Delete Log", role: .destructive) { deleteEntry() }
                    }

                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .navigationTitle(existing == nil ? "Add Watch" : "Edit Watch")
            .onAppear(perform: loadInitialState)
        }
    }

    private func loadInitialState() {
        if let e = existing {
            watchedOn = e.watchedOn ?? Date()
            whereWatched = e.whereWatched ?? .other
            withWho = e.withWho ?? ""
            notes = e.notes ?? ""
            selectedLabels = Set(e.labels ?? [])
        } else {
            whereWatched = WatchLocation(rawValue: lastWhereRaw) ?? .other
            withWho = lastWithWhoStored
            let parts = lastLabelsCSV.split(separator: ",").map { String($0) }.filter { !$0.isEmpty }
            selectedLabels = Set(parts)
            watchedOn = Date()
        }
    }

    private func save() {
        if let e = existing {
            e.watchedOn = watchedOn
            e.whereWatched = whereWatched
            e.withWho = withWho.isEmpty ? nil : withWho
            e.notes = notes.isEmpty ? nil : notes
            e.labels = Array(selectedLabels)
        } else {
            let owner = SessionManager.shared.currentOwnerId
            let entry = LogEntry(
                id: UUID(),
                createdAt: Date(),
                rating: nil,
                watchedOn: watchedOn,
                whereWatched: whereWatched,
                withWho: withWho.isEmpty ? nil : withWho,
                notes: notes.isEmpty ? nil : notes,
                labels: Array(selectedLabels),
                movie: movie,
                ownerId: owner
            )
            context.insert(entry)
        }

        // Persist defaults
        lastWhereRaw = whereWatched.rawValue
        lastWithWhoStored = withWho
        lastLabelsCSV = Array(selectedLabels).joined(separator: ",")

        SD.save(context)
        triggerSuccessHaptic()
        onSaved?()
        dismiss()
    }

    private func deleteEntry() {
        guard let e = existing else { return }
        context.delete(e)
        SD.save(context)
        triggerSuccessHaptic()
        onDeleted?()
        dismiss()
    }

    private func triggerSuccessHaptic() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

