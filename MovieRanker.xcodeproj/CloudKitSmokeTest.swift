//
//  CloudKitSmokeTest.swift
//
//  Simple optional smoke test for CloudKit access.
//
//  To invoke: call `CloudKitSmokeTest.run()` from a `.task` modifier in your `ContentView` or elsewhere during development,
//  typically wrapped in a `#if DEBUG` block to run only in debug builds.
//
//  Example:
//  ```swift
//  #if DEBUG
//  .task {
//      CloudKitSmokeTest.run()
//  }
//  #endif
//

import Foundation
import CloudKit

struct CloudKitSmokeTest {
    static func run() {
        #if DEBUG
        let record = CKRecord(recordType: "Ping")
        record["timestamp"] = Date()
        
        let privateDB = CKContainer.default().privateCloudDatabase
        
        privateDB.save(record) { savedRecord, error in
            if let error = error {
                print("[CloudKitSmokeTest] Error saving Ping record: \(error.localizedDescription)")
            } else {
                print("[CloudKitSmokeTest] Successfully saved Ping record at \(record["timestamp"] ?? "unknown time")")
            }
        }
        #endif
    }
}
