import SwiftUI

struct ToastBanner: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 4, y: 2)
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }
}

struct ToastHost<Content: View>: View {
    @Binding var message: String?
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            content
            if let msg = message {
                ToastBanner(text: msg)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation { message = nil }
                        }
                    }
            }
        }
        .animation(.easeInOut, value: message)
    }
}
