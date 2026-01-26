// Debouncer.swift
import Foundation

@MainActor
final class Debouncer {
    private var task: Task<Void, Never>?

    func schedule(after seconds: Double, _ action: @escaping @Sendable () -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
