//
//  PrivacyFilter.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import Foundation
import AppKit

class PrivacyFilter {
    static let shared = PrivacyFilter()
    
    private init() {}
    
    // MARK: - Main Filtering Method
    
    func shouldExcludeContent(_ content: String, contentType: ContentType = .text, sourceApp: String? = nil) -> (shouldExclude: Bool, reason: String?) {
        // Only check source app exclusions - everything else passes through
        if let sourceApp = sourceApp, let reason = checkSourceAppExclusions(sourceApp) {
            return (true, reason)
        }
        
        // Allow everything else
        return (false, nil)
    }
    
    // MARK: - Source App Exclusions
    
    // Only blocks truly sensitive applications (password managers, keychain access)
    // Everything else is allowed
    private func checkSourceAppExclusions(_ bundleID: String) -> String? {
        let excludedApps = [
            // Password Managers - These should always be blocked
            "com.1password.1password7",
            "com.agilebits.onepassword7",
            "com.agilebits.onepassword-osx",
            "com.agilebits.onepassword4",
            "com.bitwarden.desktop",
            "com.lastpass.LastPass",
            "com.apple.keychainaccess",
            "com.dashlane.dashlane",
            "com.keeper.KeeperDesktop",
            "com.enpass.Enpass",
            "com.nordpass.macos",
            "com.roboform.RoboForm",
            
            // System Keychain Access
            "com.apple.Keychain-Access",
            "com.apple.KeychainAccess",
            
            // Additional password managers
            "com.mela.Mela", // If it's a password manager variant
            "com.strongbox.mac.Strongbox",
            "com.macpaw.CleanMyMac4.HealthMonitor", // Sometimes stores sensitive data
        ]
        
        // Case-insensitive check for bundle IDs
        let lowercaseBundleID = bundleID.lowercased()
        
        for excludedApp in excludedApps {
            if lowercaseBundleID == excludedApp.lowercased() {
                return "Content from password manager or keychain app (\(bundleID)) is blocked for security"
            }
        }
        
        // Also block any app with "password", "keychain", or "vault" in the bundle ID
        if lowercaseBundleID.contains("password") || 
           lowercaseBundleID.contains("keychain") || 
           lowercaseBundleID.contains("vault") ||
           lowercaseBundleID.contains("1password") ||
           lowercaseBundleID.contains("bitwarden") ||
           lowercaseBundleID.contains("lastpass") ||
           lowercaseBundleID.contains("dashlane") {
            return "Content from security-related app (\(bundleID)) is blocked for privacy"
        }
        
        return nil
    }
} 