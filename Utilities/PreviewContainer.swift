import SwiftData

enum PreviewContainer {
    static func inMemory(models: [any PersistentModel.Type]) -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema(models)
        return try! ModelContainer(for: schema, configurations: config)
    }
}
