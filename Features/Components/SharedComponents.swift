import SwiftUI
import SafariServices

// 1. The Score Badge (Aligned & Expanded)
struct RatingBadge: View {
    let source: String
    let score: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(source)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(color)
                .lineLimit(1)             // Prevent wrapping
                .minimumScaleFactor(0.8)  // Shrink text slightly if name is huge
            
            Spacer()
            
            Text(score)
                .font(.system(size: 18, weight: .black, design: .rounded)) // Fixed size
                .monospacedDigit()        // Aligns numbers perfectly
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)           // Slightly taller for touch targets
        .frame(maxWidth: .infinity)       // <--- THE MAGIC FIX (Fills width)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

// 2. The "Saved" Popup
struct SuccessToast: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(text).font(.subheadline).bold()
        }
        .padding()
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// 3. The In-App Browser
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(named: "AccentColor")
        return controller
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// 4. The Stat Card
struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.heavy)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
}
