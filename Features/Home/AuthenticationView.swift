// AuthenticationView.swift
import SwiftUI

struct AuthenticationView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isSigningUp = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAlert = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Logo
                VStack(spacing: 8) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 60, weight: .light))
                        .foregroundColor(.accentColor)
                    
                    Text("MovieRanker")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Rank your favorite movies and shows")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                Spacer()
                
                // Form
                VStack(spacing: 16) {
                    // FIX: Wrapped iOS-specific modifier
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled(true)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(isSigningUp ? .newPassword : .password)
                    
                    Button(action: authenticate) {
                        HStack {
                            if isLoading { ProgressView().scaleEffect(0.8) }
                            Text(isSigningUp ? "Create Account" : "Sign In")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(email.isEmpty || password.isEmpty || isLoading)
                    
                    Button(isSigningUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isSigningUp.toggle()
                            errorMessage = nil
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Guest
                VStack(spacing: 12) {
                    Text("Or continue as guest")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button("Continue as Guest") {
                        NotificationCenter.default.post(name: .continueAsGuest, object: nil)
                    }
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                }
                .padding(.bottom, 32)
            }
            .padding()
            .alert("Authentication Error", isPresented: $showingAlert) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error occurred")
            }
        }
    }
    
    private func authenticate() {
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                if isSigningUp {
                    // Create Account
                    try await AuthService.shared.signUp(email: email, password: password)
                } else {
                    // Sign In
                    try await AuthService.shared.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
                showingAlert = true
            }
            
            isLoading = false
        }
    }
}

#Preview {
    AuthenticationView()
}
