import SwiftUI

struct PremiumBadgeView: View {
    let badge: AppBadge
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // 1. THE TOKEN BASE
                if badge.isUnlocked {
                    // UNLOCKED: Vibrant 3D Token
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [badge.color.opacity(0.8), badge.color],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: badge.color.opacity(0.5), radius: 8, x: 0, y: 4)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.6), .black.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 4
                                )
                        )
                } else {
                    // LOCKED: Slate / Etched look
                    Circle()
                        .fill(Color(white: 0.2))
                        .overlay(
                            Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                        )
                }
                
                // 2. THE ICON
                if badge.isUnlocked {
                    Image(systemName: badge.icon)
                        .font(.system(size: 30, weight: .black))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.gray.opacity(0.5))
                }
                
                // 3. SHINE EFFECT (If unlocked)
                if badge.isUnlocked {
                    Circle()
                        .trim(from: 0, to: 0.2)
                        .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-45))
                        .frame(width: 70, height: 70) // Slightly smaller than container
                        .blur(radius: 1)
                }
            }
            .frame(width: 80, height: 80)
            
            // 4. TEXT LABEL
            VStack(spacing: 2) {
                Text(badge.name)
                    .font(.caption)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(badge.isUnlocked ? .primary : .secondary)
                
                if badge.isUnlocked {
                    Text(badge.description)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(width: 80)
                }
            }
        }
        // Pop Effect when unlocked
        .scaleEffect(badge.isUnlocked ? 1.0 : 0.9)
        .opacity(badge.isUnlocked ? 1.0 : 0.6)
        .padding(.vertical, 4)
    }
}
