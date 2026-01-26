import SwiftUI

struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialUsername: String
    let initialDisplayName: String
    let onSave: (_ newUsername: String, _ newDisplayName: String) -> Void

    @State private var username: String
    @State private var displayName: String

    @State private var isChecking = false
    @State private var isAvailable: Bool? = nil

    @State private var usernameError: String? = nil
    @State private var displayNameError: String? = nil

    init(initialUsername: String, initialDisplayName: String, onSave: @escaping (_ newUsername: String, _ newDisplayName: String) -> Void) {
        self.initialUsername = initialUsername
        self.initialDisplayName = initialDisplayName
        self.onSave = onSave
        _username = State(initialValue: initialUsername)
        _displayName = State(initialValue: initialDisplayName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Username") {
                    HStack {
                        #if os(iOS)
                        TextField("@username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                        #else
                        TextField("@username", text: $username)
                        #endif
                        availabilityView
                    }
                    Text("Usernames are public and must be unique.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let err = usernameError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }

                Section("Display name") {
                    #if os(iOS)
                    TextField("Your name", text: $displayName)
                        .textInputAutocapitalization(.words)
                    #else
                    TextField("Your name", text: $displayName)
                    #endif
                    HStack {
                        Spacer()
                        let count = displayName.trimmed.count
                        Text("\(count)/40")
                            .font(.caption)
                            .foregroundStyle(count > 40 ? .red : .secondary)
                    }
                    Text("Shown in your profile. You can leave this blank to use your email.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let err = displayNameError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let u = username.trimmed.lowercased()
                        let d = displayName.trimmed
                        onSave(u, d)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onChange(of: username) { _, _ in
                usernameError = validateUsername(username)
                if usernameError == nil { Task { await checkAvailability() } }
                else { isAvailable = nil }
            }
            .onChange(of: displayName) { _, _ in
                displayNameError = validateDisplayName(displayName)
            }
        }
    }

    private func validateUsername(_ value: String) -> String? {
        let u = value.trimmed
        guard !u.isEmpty else { return nil } // optional
        // Rules: 3–20 chars, lowercase letters/numbers/underscore, must start with a letter
        let pattern = "^[a-z][a-z0-9_]{2,19}$"
        if u.range(of: pattern, options: .regularExpression) == nil {
            if u.count < 3 || u.count > 20 { return "Username must be 3–20 characters." }
            if u.first?.isLetter == false { return "Username must start with a letter." }
            return "Only lowercase letters, numbers, and underscore are allowed."
        }
        return nil
    }

    private func validateDisplayName(_ value: String) -> String? {
        let d = value.trimmed
        guard !d.isEmpty else { return nil } // optional
        if d.count > 40 { return "Display name must be 40 characters or fewer." }
        return nil
    }

    private var canSave: Bool {
        let u = username.trimmed
        let d = displayName.trimmed
        // Must satisfy local validation
        if validateUsername(u) != nil { return false }
        if validateDisplayName(d) != nil { return false }
        // Username optional; if provided and changed, require availability check to pass
        if !u.isEmpty && u.caseInsensitiveCompare(initialUsername) != .orderedSame {
            return (isAvailable == true) && !isChecking
        }
        return true
    }

    @ViewBuilder
    private var availabilityView: some View {
        let u = username.trimmed
        if usernameError != nil, !u.isEmpty {
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        } else if u.isEmpty || u.caseInsensitiveCompare(initialUsername) == .orderedSame {
            EmptyView()
        } else if isChecking {
            ProgressView().controlSize(.small)
        } else if let ok = isAvailable {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(ok ? .green : .red)
        }
    }

    @MainActor
    private func checkAvailability() async {
        let u = username.trimmed
        if validateUsername(u) != nil { isAvailable = nil; isChecking = false; return }
        guard !u.isEmpty, u.caseInsensitiveCompare(initialUsername) != .orderedSame else {
            isAvailable = nil
            isChecking = false
            return
        }
        isChecking = true
        let ok = await ProfileService.shared.isUsernameAvailable(u)
        isAvailable = ok
        isChecking = false
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

#Preview {
    EditProfileSheet(initialUsername: "", initialDisplayName: "Alex") { _, _ in }
}
