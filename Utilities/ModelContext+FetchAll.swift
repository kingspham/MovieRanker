// ModelContext+FetchAll.swift
import SwiftData

extension ModelContext {
    func fetchAll<T: PersistentModel>(_ type: T.Type = T.self) -> [T] {
        (try? fetch(FetchDescriptor<T>())) ?? []
    }

    func first<T: PersistentModel>(_ type: T.Type = T.self) -> T? {
        var fd = FetchDescriptor<T>()
        fd.fetchLimit = 1
        return (try? fetch(fd))?.first
    }
}
