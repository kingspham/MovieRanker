import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    // Binding to trigger the actual feature when they click "Start"
    @Binding var launchRapidFire: Bool
    
    var body: some View {
        ZStack {
            Color("PageBackground").ignoresSafeArea() // Or Color.white/black depending on theme
            
            VStack(spacing: 40) {
                Spacer()
                
                // ICON
                Image(systemName: "flame.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.orange)
                    .shadow(color: .orange.opacity(0.5), radius: 20, y: 10)
                
                // TEXT
                VStack(spacing: 16) {
                    Text("Welcome to Rapid Fire")
                        .font(.largeTitle).fontWeight(.heavy)
                        .multilineTextAlignment(.center)
                    
                    Text("Build your taste profile in seconds.\nRate popular movies to train your algorithm.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 32)
                }
                
                // TUTORIAL VISUAL
                HStack(spacing: 30) {
                    TutorialStep(icon: "hand.thumbsdown.fill", color: .red, text: "Dislike", swipe: "Down")
                    TutorialStep(icon: "eye.slash.fill", color: .gray, text: "Skip", swipe: "Left")
                    TutorialStep(icon: "hand.thumbsup.fill", color: .green, text: "Like", swipe: "Right")
                }
                
                Spacer()
                
                // BUTTONS
                VStack(spacing: 16) {
                    Button {
                        dismiss()
                        // Slight delay to allow sheet to close before pushing new view
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            launchRapidFire = true
                        }
                    } label: {
                        Text("Start Rating")
                            .font(.headline).bold()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .shadow(color: .orange.opacity(0.3), radius: 10, y: 5)
                    
                    Button("Maybe Later") {
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
            }
        }
    }
    
    func TutorialStep(icon: String, color: Color, text: String, swipe: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(color)
                .frame(width: 60, height: 60)
                .background(color.opacity(0.1))
                .clipShape(Circle())
            
            Text(swipe)
                .font(.caption).bold()
                .foregroundStyle(.secondary)
        }
    }
}
