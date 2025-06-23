//
//  ContentHashingUtility.swift
//  kopi iOS
//
//  Created by Wan Menzy on 20/06/2025.
//

import Foundation
import CryptoKit
import UIKit

struct ContentHashingUtility {
    
    /// Generate SHA-256 hash for content deduplication and reconciliation
    static func generateContentHash(from content: String) -> String {
        let data = content.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Generate device identifier for tracking item origin
    static func getDeviceIdentifier() -> String {
        return getiOSDeviceIdentifier()
    }
    
    /// Get human-readable device name
    static func getDeviceName() -> String {
        return getiOSDeviceName()
    }
    
    /// Compare two content hashes for reconciliation
    static func compareContentHashes(_ hash1: String, _ hash2: String) -> Bool {
        return hash1 == hash2
    }
}

// MARK: - iOS Device Identification
private extension ContentHashingUtility {
    
    static func getiOSDeviceIdentifier() -> String {
        // Use identifierForVendor as a stable identifier
        guard let vendorID = UIDevice.current.identifierForVendor?.uuidString else {
            return "ios-unknown"
        }
        
        // Create a shorter hash for the identifier
        let hashedVendor = generateContentHash(from: vendorID)
        return "ios-\(String(hashedVendor.prefix(8)))"
    }
    
    static func getiOSDeviceName() -> String {
        return UIDevice.current.name
    }
} 