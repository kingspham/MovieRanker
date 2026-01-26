import SwiftUI
import SwiftData

/// Simple compare view for ranking movies
struct CompareView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    
    let seed: Movie?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.yellow)
                
                Text("Ranking Feature")
                    .font(.title)
                    .bold()
                
                Text("Compare and rank your watched movies")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                
                Text("Coming soon!")
                    .font(.headline)
                    .foregroundStyle(.blue)
            }
            .padding()
            .navigationTitle("Rank Movies")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
