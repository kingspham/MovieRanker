import SwiftData

// Shared, app-wide helper to read all rows of a SwiftData model.
extension ModelContext {
    func fetchAll<T: PersistentModel>(_ type: T.Type = T.self) -> [T] {
        (try? fetch(FetchDescriptor<T>())) ?? []
    }
}
