//
//  DeviceManager.swift
//  kopi
//
//  Created by AI Assistant on 19/06/2025.
//

import Foundation
import AppKit

struct DeviceInfo {
    let deviceID: String
    let deviceName: String
    let deviceType: String
    let osVersion: String
    let appVersion: String
    let registrationDate: Date
}

enum SyncSource: String, CaseIterable {
    case localCopy = "local_copy"
    case universalClipboard = "universal_clipboard"
    case cloudKitSync = "cloudkit_sync"
    
    var displayName: String {
        switch self {
        case .localCopy:
            return "Local Copy"
        case .universalClipboard:
            return "Universal Clipboard"
        case .cloudKitSync:
            return "CloudKit Sync"
        }
    }
}

class DeviceManager: ObservableObject {
    static let shared = DeviceManager()
    
    private let deviceIDKey = "KopiDeviceID"
    private let deviceInfoKey = "KopiDeviceInfo"
    
    @Published private(set) var deviceID: String
    @Published private(set) var deviceInfo: DeviceInfo
    
    private init() {
        // Initialize or retrieve device ID
        let finalDeviceID: String
        if let existingID = UserDefaults.standard.string(forKey: deviceIDKey) {
            finalDeviceID = existingID
        } else {
            finalDeviceID = Self.generateDeviceID()
            UserDefaults.standard.set(finalDeviceID, forKey: deviceIDKey)
        }
        self.deviceID = finalDeviceID
        
        // Create device info
        self.deviceInfo = Self.createDeviceInfo(deviceID: finalDeviceID)
        
        // Store device info for debugging/analytics
        if let data = try? JSONEncoder().encode(self.deviceInfo) {
            UserDefaults.standard.set(data, forKey: deviceInfoKey)
        }
        
        print("🔧 [DeviceManager] Device initialized: \(self.deviceID)")
        print("📱 [DeviceManager] Device info: \(self.deviceInfo.deviceName) (\(self.deviceInfo.deviceType))")
    }
    
    // MARK: - Public Methods
    
    /// Get a unique identifier for this device installation
    func getDeviceID() -> String {
        return deviceID
    }
    
    /// Get comprehensive device information
    func getDeviceInfo() -> DeviceInfo {
        return deviceInfo
    }
    
    /// Check if this device initiated a clipboard action (vs received it)
    func isInitiatingDevice(for clipboardItem: ClipboardItem) -> Bool {
        return clipboardItem.initiatingDevice == deviceID
    }
    
    /// Create a new canonical ID for a clipboard item originated on this device
    func createCanonicalID() -> UUID {
        return UUID()
    }
    
    /// Determine if a clipboard event is likely from Universal Clipboard
    func detectUniversalClipboardTransfer(content: String, timestamp: Date) -> Bool {
        // Check timing - Universal Clipboard typically transfers within 1-3 seconds
        let timeSinceLastLocalCopy = Date().timeIntervalSince(timestamp)
        
        // If we just copied something locally within the last 10 seconds, 
        // and now we're seeing the same content, it's likely Universal Clipboard
        return timeSinceLastLocalCopy > 0.5 && timeSinceLastLocalCopy < 10.0
    }
    
    // MARK: - Private Methods
    
    private static func generateDeviceID() -> String {
        // Create a unique, persistent device identifier
        // Format: platform-timestamp-random
        let platform = "mac"
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let random = String(Int.random(in: 1000...9999))
        
        return "\(platform)-\(timestamp)-\(random)"
    }
    
    private static func createDeviceInfo(deviceID: String) -> DeviceInfo {
        // Get system information
        let deviceName = Host.current().localizedName ?? "Unknown Mac"
        let deviceType = "macOS"
        
        // Get OS version
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        
        // Get app version (you may need to adjust this based on your Info.plist)
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        
        return DeviceInfo(
            deviceID: deviceID,
            deviceName: deviceName,
            deviceType: deviceType,
            osVersion: osVersion,
            appVersion: appVersion,
            registrationDate: Date()
        )
    }
}

// MARK: - DeviceInfo Extensions

extension DeviceInfo: Codable {}

extension DeviceInfo: CustomStringConvertible {
    var description: String {
        return "\(deviceName) (\(deviceType) \(osVersion)) - ID: \(deviceID)"
    }
} 