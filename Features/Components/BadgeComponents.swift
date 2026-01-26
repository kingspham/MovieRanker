import SwiftUI

struct PremiumBadgeView: View {
    let badge: AppBadge
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if badge.isUnlocked {
                    // UNLOCKED: Colorful
                    Circle()
                        .fill(badge.color.gradient)
                        .shadow(color: badge.color.opacity(0.3), radius: 4, x: 0, y: 2)
                        .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 2))
                    
                    Image(systemName: badge.icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 1)
                } else {
                    // LOCKED: Simple Gray (Performance Optimization)
                    Circle()
                        .fill(Color.gray.opacity(0.15))
                        .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    
                    Image(systemName: "lock.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.gray.opacity(0.4))
                }
            }
            .frame(width: 64, height: 64) // Fixed Size
            
            Text(badge.name)
                .font(.system(size: 10, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(badge.isUnlocked ? .primary : .secondary)
                .lineLimit(1)
                .frame(width: 70)
        }
        .opacity(badge.isUnlocked ? 1.0 : 0.5)
    }
}
