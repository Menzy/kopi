//
//  SourceAppDetector.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import Foundation
import AppKit
import ApplicationServices

struct SourceAppInfo {
    let bundleID: String?
    let name: String?
    let iconData: Data?
}

class SourceAppDetector {
    static let shared = SourceAppDetector()
    
    private init() {}
    
    func detectCurrentApp() -> SourceAppInfo {
        // Try to get the frontmost application using NSWorkspace (most reliable)
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            // Skip our own app - we want the app that was active before us
            if frontmostApp.bundleIdentifier == "com.wanmenzy.kopi" || 
               frontmostApp.bundleIdentifier == Bundle.main.bundleIdentifier {
                // Get the previously active app
                return getPreviouslyActiveApp()
            }
            
            return SourceAppInfo(
                bundleID: frontmostApp.bundleIdentifier,
                name: frontmostApp.localizedName,
                iconData: getAppIconData(for: frontmostApp)
            )
        }
        
        // Last resort: return unknown
        return SourceAppInfo(bundleID: nil, name: "Unknown", iconData: nil)
    }
    
    func checkAccessibilityPermissions() -> Bool {
        // Check if we have accessibility permissions
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func requestAccessibilityPermissions() {
        // This will prompt the user to grant accessibility permissions
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    // MARK: - Private Methods
    
    private func getAppIconData(for app: NSRunningApplication) -> Data? {
        guard let icon = app.icon else { return nil }
        return getIconData(from: icon)
    }
    
    private func getAppIconData(forBundleID bundleID: String) -> Data? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        
        // Try to load the icon
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        return getIconData(from: icon)
    }
    
    private func getIconData(from icon: NSImage) -> Data? {
        // Resize icon to a reasonable size (32x32)
        let targetSize = NSSize(width: 32, height: 32)
        let resizedIcon = NSImage(size: targetSize)
        
        resizedIcon.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: targetSize))
        resizedIcon.unlockFocus()
        
        // Convert to PNG data
        guard let tiffData = resizedIcon.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        return pngData
    }
    
    private func getPreviouslyActiveApp() -> SourceAppInfo {
        // Get all running applications, excluding our own
        let runningApps = NSWorkspace.shared.runningApplications
        let ourBundleID = Bundle.main.bundleIdentifier
        
        // Find the most recently active app that's not us
        let otherApps = runningApps.filter { app in
            app.bundleIdentifier != ourBundleID &&
            app.bundleIdentifier != "com.wanmenzy.kopi" &&
            app.activationPolicy == .regular &&
            !app.isTerminated
        }
        
        // Sort by activation order (most recent first) and get the first one
        if let previousApp = otherApps.first {
            return SourceAppInfo(
                bundleID: previousApp.bundleIdentifier,
                name: previousApp.localizedName,
                iconData: getAppIconData(for: previousApp)
            )
        }
        
        return SourceAppInfo(bundleID: nil, name: "Unknown", iconData: nil)
    }
}

// MARK: - Extensions for Accessibility

extension SourceAppDetector {
    func getAccessibilityStatus() -> AccessibilityStatus {
        if AXIsProcessTrusted() {
            return .granted
        } else {
            return .denied
        }
    }
    
    enum AccessibilityStatus {
        case granted
        case denied
        
        var description: String {
            switch self {
            case .granted:
                return "Accessibility permissions granted"
            case .denied:
                return "Accessibility permissions required for source app detection"
            }
        }
    }
} 