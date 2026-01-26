//
//  PredictedRatingBadge.swift
//  MovieRanker
//

import SwiftUI

/// A small pill showing a predicted rating (0…100) with color cue.
/// Use in search rows, info pages, lists, etc.
struct PredictedRatingBadge: View {
    let value: Double   // 0…100

    var body: some View {
        let text = "\(Int(round(value)))"
        return Text(text)
            .font(.caption.bold())
            .monospacedDigit()
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .foregroundStyle(.white)
            .background(color(for: value), in: Capsule())
            .accessibilityLabel("Predicted rating \(text) out of 100")
    }

    private func color(for v: Double) -> Color {
        switch v {
        case ..<40: return .red
        case 40..<60: return .orange
        case 60..<75: return .yellow
        case 75..<88: return .green
        default: return .blue
        }
    }
}
