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
        
        // Capture initial frontmost app
        lastFrontmostApp = sourceAppDetector.detectCurrentApp()
        
        // Start moderate-frequency timer-based monitoring (polling every 0.2 seconds for good responsiveness without overwhelming)
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.checkClipboardChanges()
        }
        
        print("📋 Clipboard monitoring started successfully!")
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)
    }
    
    func forceCheck() {
        // Manual method to force an immediate clipboard check
        checkClipboardChanges()
    }
    
    // MARK: - Private Methods
    
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
        
        // Capture the frontmost app IMMEDIATELY before any async operations
        let sourceApp = lastFrontmostApp ?? sourceAppDetector.detectCurrentApp()
        lastFrontmostApp = sourceAppDetector.detectCurrentApp() // Update for next time
        
        // IMMEDIATELY save to local storage on main thread - no delays
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
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