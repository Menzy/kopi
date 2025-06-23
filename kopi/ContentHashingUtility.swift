//
//  ContentHashingUtility.swift
//  kopi
//
//  Created by Wan Menzy on 20/06/2025.
//

import Foundation
import CryptoKit
import IOKit

struct ContentHashingUtility {
    
    /// Generate SHA-256 hash for content deduplication and reconciliation
    static func generateContentHash(from content: String) -> String {
        let data = content.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Generate device identifier for tracking item origin
    static func getDeviceIdentifier() -> String {
        #if os(macOS)
        return getMacDeviceIdentifier()
        #elseif os(iOS)
        return getiOSDeviceIdentifier()
        #else
        return "unknown-device"
        #endif
    }
    
    /// Get human-readable device name
    static func getDeviceName() -> String {
        #if os(macOS)
        return getMacDeviceName()
        #elseif os(iOS)
        return getiOSDeviceName()
        #else
        return "Unknown Device"
        #endif
    }
    
    /// Compare two content hashes for reconciliation
    static func compareContentHashes(_ hash1: String, _ hash2: String) -> Bool {
        return hash1 == hash2
    }
}

// MARK: - macOS Device Identification
#if os(macOS)
private extension ContentHashingUtility {
    
    static func getMacDeviceIdentifier() -> String {
        // Use IOKit to get a unique hardware identifier
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        
        guard platformExpert > 0 else {
            return "mac-unknown"
        }
        
        defer { IOObjectRelease(platformExpert) }
        
        guard let serialNumber = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformSerialNumberKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String else {
            return "mac-unknown"
        }
        
        // Create a hash of the serial number for privacy
        let hashedSerial = generateContentHash(from: serialNumber)
        return "mac-\(String(hashedSerial.prefix(8)))"
    }
    
    static func getMacDeviceName() -> String {
        return Host.current().localizedName ?? "Mac"
    }
}
#endif

// MARK: - iOS Device Identification
#if os(iOS)
import UIKit

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
#endif 