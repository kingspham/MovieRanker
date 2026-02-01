import SwiftUI

struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialUsername: String
    let initialDisplayName: String
    let initialBio: String
    let initialFavoriteMovie: String
    let initialFavoriteShow: String
    let initialFavoriteBook: String
    let initialFavoritePodcast: String
    let initialHomeCity: String
    let onSave: (ProfileUpdate) -> Void

    @State private var username: String
    @State private var displayName: String
    @State private var bio: String
    @State private var favoriteMovie: String
    @State private var favoriteShow: String
    @State private var favoriteBook: String
    @State private var favoritePodcast: String
    @State private var homeCity: String

    @State private var isChecking = false
    @State private var isAvailable: Bool? = nil

    @State private var usernameError: String? = nil
    @State private var displayNameError: String? = nil

    struct ProfileUpdate {
        let username: String
        let displayName: String
        let bio: String
        let favoriteMovie: String
        let favoriteShow: String
        let favoriteBook: String
        let favoritePodcast: String
        let homeCity: String
    }

    // Convenience initializer for backward compatibility
    init(initialUsername: String, initialDisplayName: String, onSave: @escaping (_ newUsername: String, _ newDisplayName: String) -> Void) {
        self.init(
            initialUsername: initialUsername,
            initialDisplayName: initialDisplayName,
            initialBio: "",
            initialFavoriteMovie: "",
            initialFavoriteShow: "",
            initialFavoriteBook: "",
            initialFavoritePodcast: "",
            initialHomeCity: "",
            onSave: { update in
                onSave(update.username, update.displayName)
            }
        )
    }

    init(
        initialUsername: String,
        initialDisplayName: String,
        initialBio: String,
        initialFavoriteMovie: String,
        initialFavoriteShow: String,
        initialFavoriteBook: String,
        initialFavoritePodcast: String,
        initialHomeCity: String,
        onSave: @escaping (ProfileUpdate) -> Void
    ) {
        self.initialUsername = initialUsername
        self.initialDisplayName = initialDisplayName
        self.initialBio = initialBio
        self.initialFavoriteMovie = initialFavoriteMovie
        self.initialFavoriteShow = initialFavoriteShow
        self.initialFavoriteBook = initialFavoriteBook
        self.initialFavoritePodcast = initialFavoritePodcast
        self.initialHomeCity = initialHomeCity
        self.onSave = onSave
        _username = State(initialValue: initialUsername)
        _displayName = State(initialValue: initialDisplayName)
        _bio = State(initialValue: initialBio)
        _favoriteMovie = State(initialValue: initialFavoriteMovie)
        _favoriteShow = State(initialValue: initialFavoriteShow)
        _favoriteBook = State(initialValue: initialFavoriteBook)
        _favoritePodcast = State(initialValue: initialFavoritePodcast)
        _homeCity = State(initialValue: initialHomeCity)
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

                Section("Display Name") {
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
                    if let err = displayNameError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }

                Section("Bio") {
                    TextField("Tell us about yourself...", text: $bio, axis: .vertical)
                        .lineLimit(3...6)
                    HStack {
                        Spacer()
                        let count = bio.count
                        Text("\(count)/160")
                            .font(.caption)
                            .foregroundStyle(count > 160 ? .red : .secondary)
                    }
                }

                Section("Favorites") {
                    HStack {
                        Image(systemName: "film.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        TextField("Favorite Movie", text: $favoriteMovie)
                    }
                    HStack {
                        Image(systemName: "tv.fill")
                            .foregroundStyle(.purple)
                            .frame(width: 24)
                        TextField("Favorite TV Show", text: $favoriteShow)
                    }
                    HStack {
                        Image(systemName: "book.fill")
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                        TextField("Favorite Book", text: $favoriteBook)
                    }
                    HStack {
                        Image(systemName: "mic.fill")
                            .foregroundStyle(.green)
                            .frame(width: 24)
                        TextField("Favorite Podcast", text: $favoritePodcast)
                    }
                }

                Section("Location") {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.red)
                            .frame(width: 24)
                        TextField("Home City", text: $homeCity)
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
                        let update = ProfileUpdate(
                            username: username.trimmed.lowercased(),
                            displayName: displayName.trimmed,
                            bio: bio.trimmed,
                            favoriteMovie: favoriteMovie.trimmed,
                            favoriteShow: favoriteShow.trimmed,
                            favoriteBook: favoriteBook.trimmed,
                            favoritePodcast: favoritePodcast.trimmed,
                            homeCity: homeCity.trimmed
                        )
                        onSave(update)
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
        guard !d.isEmpty else { return nil }
        if d.count > 40 { return "Display name must be 40 characters or fewer." }
        return nil
    }

    private var canSave: Bool {
        let u = username.trimmed
        let d = displayName.trimmed
        if validateUsername(u) != nil { return false }
        if validateDisplayName(d) != nil { return false }
        if bio.count > 160 { return false }
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
        try? await Task.sleep(nanoseconds: 500_000_000)
        isAvailable = true
        isChecking = false
    }
}

#Preview {
    EditProfileSheet(initialUsername: "", initialDisplayName: "Alex") { _, _ in }
}
