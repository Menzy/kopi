//
//  ClipboardMonitor.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import Foundation
import AppKit
import Combine
import Cocoa
import CoreData
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Notifications
extension Notification.Name {
    static let clipboardDidChange = Notification.Name("clipboardDidChange")
}

class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()
    
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = 0
    private var monitoringTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // Track clipboard changes made by this app to avoid loops
    private var lastAppCopyContent: String?
    private var lastAppCopyTime: Date?
    
    // Track the frontmost app before clipboard changes
    private var lastFrontmostApp: SourceAppInfo?
    
    // IMMEDIATE SOURCE APP CAPTURE - capture the active app continuously
    private var currentActiveApp: SourceAppInfo?
    private var appTrackingTimer: Timer?
    
    // Published properties for UI updates
    @Published var isMonitoring: Bool = false
    @Published var lastClipboardContent: String = ""
    @Published var clipboardDidChange: Bool = false
    
    private var dataManager: ClipboardDataManager!
    private let sourceAppDetector = SourceAppDetector.shared
    private let privacyFilter = PrivacyFilter.shared
    
    init() {
        lastChangeCount = pasteboard.changeCount
        print("📋 Clipboard monitoring initialized")
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        lastChangeCount = pasteboard.changeCount
        
        // IMMEDIATE SOURCE APP TRACKING - Track active app continuously at high frequency
        // This ensures we always have the correct source app before clipboard changes
        currentActiveApp = sourceAppDetector.detectCurrentApp()
        lastFrontmostApp = currentActiveApp
        
        // Listen for app activation changes using NSWorkspace notifications for instant updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        // Start HIGH-FREQUENCY app tracking (every 50ms) to catch app switches immediately
        appTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.trackActiveApp()
        }
        
        // Start IMMEDIATE clipboard monitoring (every 50ms for instant detection)
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkClipboardChanges()
        }
        
        print("📋 Clipboard monitoring started with immediate source app tracking!")
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        appTrackingTimer?.invalidate()
        appTrackingTimer = nil
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWorkspace.didActivateApplicationNotification, object: nil)
        
        print("📋 Clipboard monitoring stopped")
    }
    
    func forceCheck() {
        // Manual method to force an immediate clipboard check
        checkClipboardChanges()
    }
    
    // MARK: - Private Methods
    
    // MARK: - Feedback Methods
    
    private func playClipboardSound() {
        // This will play whatever sound the user has selected in System Preferences > Sound > Alert sound
        NSSound.beep()
    }
    
    private func animateMenuBarIcon() {
        // Trigger menu bar icon animation
        DispatchQueue.main.async {
            MenuBarManager.shared.animateIcon()
        }
    }
    
    // INSTANT APP ACTIVATION DETECTION - triggered immediately when apps switch
    @objc private func appDidActivate(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            let newActiveApp = SourceAppInfo(
                bundleID: app.bundleIdentifier,
                name: app.localizedName,
                iconData: getAppIconData(for: app)
            )
            
            // Update immediately on app switch
            currentActiveApp = newActiveApp
            print("🚀 INSTANT app switch detected: \(newActiveApp.name ?? "Unknown") (\(newActiveApp.bundleID ?? "unknown"))")
        }
    }
    
    // Helper method to get app icon data
    private func getAppIconData(for app: NSRunningApplication) -> Data? {
        guard let icon = app.icon else { return nil }
        
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
    
    // IMMEDIATE SOURCE APP TRACKING - continuously track the active app
    private func trackActiveApp() {
        let newActiveApp = sourceAppDetector.detectCurrentApp()
        
        // Only update if the app actually changed (avoid unnecessary work)
        if newActiveApp.bundleID != currentActiveApp?.bundleID {
            currentActiveApp = newActiveApp
            // Don't print for our own app to reduce noise
            if newActiveApp.bundleID != Bundle.main.bundleIdentifier && 
               newActiveApp.bundleID != "com.wanmenzy.kopi" {
                print("🎯 Active app changed to: \(newActiveApp.name ?? "Unknown") (\(newActiveApp.bundleID ?? "unknown"))")
            }
        }
    }
    
    private func checkClipboardChanges() {
        let currentChangeCount = pasteboard.changeCount
        
        // Quick exit if change count hasn't changed
        guard currentChangeCount != lastChangeCount else { return }
        
        // Update the change count immediately to prevent race conditions
        lastChangeCount = currentChangeCount
        
        // IMMEDIATELY capture clipboard content and source app while still on timer thread
        // This prevents delays that could cause wrong source app detection
        guard let clipboardContent = getClipboardContent() else { return }
        
        // Check if we should ignore this clipboard change
        if shouldIgnoreClipboardChange(content: clipboardContent.content) {
            return
        }
        
        // USE THE CONTINUOUSLY TRACKED SOURCE APP - this is the app that was active when copy happened
        // Since we track the active app continuously, currentActiveApp contains the correct source
        let sourceApp = currentActiveApp ?? sourceAppDetector.detectCurrentApp()
        
        print("📋 Clipboard change detected! Source app: \(sourceApp.name ?? "Unknown") (\(sourceApp.bundleID ?? "unknown"))")
        
        // IMMEDIATELY save to local storage on main thread - no delays
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // INSTANT FEEDBACK: Play sound and animate icon immediately
            self.playClipboardSound()
            self.animateMenuBarIcon()
            
            // Save immediately to local Core Data storage
            let dataManager = ClipboardDataManager.shared

            let _ = dataManager.createClipboardItem(
                content: clipboardContent.content,
                contentType: clipboardContent.type,
                sourceApp: sourceApp.bundleID,
                sourceAppName: sourceApp.name,
                sourceAppIcon: sourceApp.iconData
            )
            
            // Update UI immediately
            self.lastClipboardContent = clipboardContent.content
            self.clipboardDidChange.toggle() // Trigger UI refresh
            
            // CloudKit sync happens automatically in ClipboardDataManager.createClipboardItem
            // so both local storage and cloud sync are handled properly

            print("📋 Clipboard item saved immediately: \(clipboardContent.content.prefix(30))... from \(sourceApp.name ?? "Unknown")")
        }
    }
    
    // Simplified and more reliable clipboard content detection
    private func getClipboardContent() -> ClipboardContent? {
        let pasteboard = NSPasteboard.general
        
        // 1. Check for images first (most specific)
        if let imageData = pasteboard.data(forType: .png) ?? 
                           pasteboard.data(forType: .tiff) {
            // Basic validation - just check if we can create an image
            if let _ = NSImage(data: imageData), imageData.count > 1000 { // Minimum size to avoid tiny icons
                let base64String = imageData.base64EncodedString()
                return ClipboardContent(content: base64String, type: .image)
            }
        }
        
        // 2. Check for URLs (before text since URLs are also strings)
        if let urlString = pasteboard.string(forType: .URL) {
            return ClipboardContent(content: urlString, type: .url)
        }
        
        // 3. Check for text content
        if let text = pasteboard.string(forType: .string) {
            // Simple URL detection
            if text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("ftp://") {
                return ClipboardContent(content: text, type: .url)
            } else {
                return ClipboardContent(content: text, type: .text)
            }
        }
        
        // 4. Check for file URLs
        if let fileURL = pasteboard.string(forType: .fileURL) {
            return ClipboardContent(content: fileURL, type: .url)
        }
        
        return nil
    }
    
    // MARK: - App Copy Tracking
    
    // Call this method when the app copies something to the clipboard
    // This helps avoid detecting our own clipboard changes
    func notifyAppCopiedToClipboard(content: String) {
        lastAppCopyContent = content
        lastAppCopyTime = Date()
    }
    
    // Check if a clipboard change should be ignored (was made by this app)
    private func shouldIgnoreClipboardChange(content: String) -> Bool {
        // If we recently copied this exact content, ignore it
        if let lastContent = lastAppCopyContent,
           let lastTime = lastAppCopyTime,
           lastContent == content,
           Date().timeIntervalSince(lastTime) < 5.0 { // 5 second window
            return true
        }
        
        return false
    }
}

// MARK: - Supporting Types

struct ClipboardContent {
    let content: String
    let type: ContentType
}

extension NSPasteboard.PasteboardType {
    static let jpeg = NSPasteboard.PasteboardType("public.jpeg")
} 