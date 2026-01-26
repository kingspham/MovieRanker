import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var importer: ImportService = .shared
    @State private var pickedData: Data?
    @State private var showFile = false

    var body: some View {
        List {
            Section("Import") {
                Button {
                    showFile = true
                } label: {
                    Label("Choose CSV (Letterboxd / Trakt / Generic)", systemImage: "tray.and.arrow.down")
                }
                .fileImporter(isPresented: $showFile, allowedContentTypes: [.commaSeparatedText, .text]) { res in
                    switch res {
                    case .success(let url):
                        do { pickedData = try Data(contentsOf: url) } catch { pickedData = nil }
                        Task {
                            if let data = pickedData {
                                await importer.runImport(data: data, context: context)
                            }
                        }
                    case .failure:
                        break
                    }
                }

                if importer.isRunning {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: importer.progress)
                        Text(importer.message).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if !importer.errors.isEmpty {
                    NavigationLink {
                        List(importer.errors, id: \.self) { Text($0) }
                            .navigationTitle("Import Errors")
                    } label: {
                        Label("View Errors (\(importer.errors.count))", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            Section("Options") {
                Toggle("Sync to Cloud After Import", isOn: $importer.syncAfterImport)
            }

            if !importer.lastImportIDs.isEmpty {
                Section {
                    Button(role: .destructive) {
                        importer.undoLastImport(context: context)
                    } label: {
                        Label("Undo Last Import", systemImage: "arrow.uturn.backward")
                    }
                }
            }

            Section("Tips") {
                Text("• Letterboxd: Export → Diary CSV")
                Text("• Trakt: History CSV (movies)")
                Text("• Generic: Include at least Title; Year and Date increase match accuracy.")
            }
        }
        .navigationTitle("Import")
    }
}

extension UTType {
    static var commaSeparatedText: UTType { UTType(importedAs: "public.comma-separated-values-text") }
}
