// DocumentPicker.swift
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit

// MARK: - iOS Implementation
struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.commaSeparatedText], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#else
import AppKit

// MARK: - Mac Placeholder Implementation
// These are dummy views to prevent the app from crashing on Mac.
struct DocumentPicker: View {
    var onPick: (URL) -> Void
    var body: some View {
        Text("Document Picking not supported on Mac yet")
            .padding()
    }
}

struct ShareSheet: View {
    var items: [Any]
    var body: some View {
        Text("Sharing not supported on Mac yet")
            .padding()
    }
}
#endif
