//
//  SessionManager+OwnerId.swift
//  
//  Provides a unified owner ID used across the app.
//
//  Created by Developer on 2025-11-04.
//

import Foundation

extension SessionManager {
    var currentOwnerId: String {
        userId ?? "guest"
    }
}
