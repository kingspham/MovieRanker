import SwiftData
import Foundation

enum SD {
    static func save(_ context: ModelContext, file: StaticString = #fileID, line: UInt = #line) {
        do {
            try context.save()
        } catch {
            // Surface SwiftData errors in console so we stop guessing
            print("[SwiftData save failed] \(error) @ \(file):\(line)")
            assertionFailure(error.localizedDescription)
        }
    }
}
