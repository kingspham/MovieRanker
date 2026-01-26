// SpinWheelView.swift
import SwiftUI
import SwiftData
#if os(iOS)
import UIKit // Only import UIKit on iOS
#endif

struct SpinWheelView: View {
    @Environment(\.dismiss) private var dismiss
    let items: [Movie]
    
    @State private var currentIndex = 0
    @State private var isSpinning = true
    @State private var winner: Movie? = nil
    
    // Haptic Feedback (iOS Only)
    #if os(iOS)
    private let generator = UIImpactFeedbackGenerator(style: .medium)
    #endif
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 40) {
                Text(isSpinning ? "Picking..." : "Watch This!")
                    .font(.title).fontWeight(.black)
                    .foregroundStyle(.white)
                    .padding(.top, 50)
                
                // THE SLOT MACHINE
                if !items.isEmpty {
                    let item = items[currentIndex]
                    
                    VStack(spacing: 20) {
                        if let path = item.posterPath {
                            // Note: Ensure your TMDbAPI has .w500 in ImageSize enum, otherwise use .w342
                            AsyncImage(url: TMDbClient.makeImageURL(path: path, size: .w500)) { p in
                                if let i = p.image {
                                    i.resizable().scaledToFill()
                                        .frame(width: 220, height: 330)
                                        .cornerRadius(16)
                                        .shadow(color: .white.opacity(0.2), radius: 20)
                                } else {
                                    Rectangle().fill(Color.gray).frame(width: 220, height: 330).cornerRadius(16)
                                }
                            }
                        } else {
                            Rectangle().fill(Color.gray).frame(width: 220, height: 330).cornerRadius(16)
                        }
                        
                        Text(item.title)
                            .font(.title2).bold()
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(height: 60)
                            .padding(.horizontal)
                    }
                }
                
                Spacer()
                
                if let _ = winner {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.headline).bold()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                } else {
                    Spacer().frame(height: 80)
                }
            }
        }
        .onAppear {
            startSpin()
        }
    }
    
    private func startSpin() {
        guard !items.isEmpty else { dismiss(); return }
        
        var delay = 0.05
        var count = 0
        let totalSpins = Int.random(in: 20...30) // How many flips before stopping
        
        func spin() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // Advance index
                currentIndex = (currentIndex + 1) % items.count
                
                // Trigger Haptic (iOS Only)
                #if os(iOS)
                generator.impactOccurred()
                #endif
                
                count += 1
                
                if count < totalSpins {
                    // Keep spinning, slightly slower
                    delay += 0.005
                    spin()
                } else {
                    // STOP
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        isSpinning = false
                        winner = items[currentIndex]
                    }
                    
                    // Success Haptic (iOS Only)
                    #if os(iOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                }
            }
        }
        
        spin()
    }
}
