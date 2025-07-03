//
//  CloudKitError.swift
//  kopi
//
//  Created by Wan Menzy on 20/06/2025.
//

import Foundation

// MARK: - CloudKit Errors

enum CloudKitError: LocalizedError {
    case notConnected
    case invalidData(String)
    case saveFailure(Error)
    case fetchFailure(Error)
    case deleteFailure(Error)
    case subscriptionFailure(Error)
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No internet connection available"
        case .invalidData(let message):
            return "Invalid data: \(message)"
        case .saveFailure(let error):
            return "Failed to save to CloudKit: \(error.localizedDescription)"
        case .fetchFailure(let error):
            return "Failed to fetch from CloudKit: \(error.localizedDescription)"
        case .deleteFailure(let error):
            return "Failed to delete from CloudKit: \(error.localizedDescription)"
        case .subscriptionFailure(let error):
            return "Failed to subscribe to CloudKit: \(error.localizedDescription)"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let cloudKitSyncCompleted = Notification.Name("cloudKitSyncCompleted")
}
