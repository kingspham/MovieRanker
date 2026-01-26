import SwiftUI

struct AuthenticationView: View {
    @StateObject private var sessionManager = SessionManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isSigningUp = false
    @State private var showingAlert = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // App Logo/Title
                VStack(spacing: 8) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 60, weight: .light))
                        .foregroundStyle(Color.accentColor)
                    
                    Text("MovieRanker")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Rank your favorite movies and shows")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                Spacer()
                
                // Authentication Form
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                    
                    Button(action: authenticate) {
                        HStack {
                            if sessionManager.isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            }
                            Text(isSigningUp ? "Create Account" : "Sign In")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(email.isEmpty || password.isEmpty || sessionManager.isLoading)
                    
                    Button(isSigningUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isSigningUp.toggle()
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Guest Mode Option
                VStack(spacing: 12) {
                    Text("Or continue as guest")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Button("Continue as Guest") {
                        Task {
                            await sessionManager.setGuestMode()
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                }
                .padding(.bottom, 32)
            }
            .padding()
            .alert("Authentication Error", isPresented: $showingAlert) {
                Button("OK") { 
                    sessionManager.authErrorMessage = nil
                }
            } message: {
                Text(sessionManager.authErrorMessage ?? "Unknown error occurred")
            }
            .onChange(of: sessionManager.authErrorMessage) { _, newValue in
                showingAlert = newValue != nil
            }
        }
    }
    
    private func authenticate() {
        Task {
            if isSigningUp {
                await sessionManager.signUp(email: email, password: password)
            } else {
                await sessionManager.signIn(email: email, password: password)
            }
        }
    }
}

#Preview {
    AuthenticationView()
}