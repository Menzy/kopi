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

class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()
    
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = 0
    private var lastContentHash: Int = 0
    private var monitoringTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // Track clipboard changes made by this app to avoid loops
    private var lastAppCopyContent: String?
    private var lastAppCopyTime: Date?
    
    // Phase 3: Universal Handoff Detection
    private var lastHandoffDetectionTime: Date?
    private let handoffDetectionWindow: TimeInterval = 2.0 // 2 seconds to detect handoff
    
    @Published var isMonitoring: Bool = false
    @Published var lastClipboardContent: String = ""
    @Published var clipboardDidChange: Bool = false
    
    private let dataManager = ClipboardDataManager.shared
    private let sourceAppDetector = SourceAppDetector.shared
    private let privacyFilter = PrivacyFilter.shared
    
    private init() {
        lastChangeCount = pasteboard.changeCount
        setupHandoffNotifications()
    }
    
    // MARK: - Phase 3: Universal Handoff Setup
    
    private func setupHandoffNotifications() {
        // Listen for handoff-related system notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NSApplicationWillContinueUserActivityNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.prepareForHandoffDetection()
        }
        
        // Monitor for handoff activity types
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NSApplicationDidContinueUserActivityNotification"), 
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handlePotentialHandoffActivity(notification)
        }
    }
    
    private func prepareForHandoffDetection() {
        lastHandoffDetectionTime = Date()
        print("🔄 [MacBook Relay] Preparing for potential handoff detection")
    }
    
    private func handlePotentialHandoffActivity(_ notification: Notification) {
        print("🔄 [MacBook Relay] Potential handoff activity detected")
        // Immediate clipboard check after handoff activity
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.forceCheck()
        }
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        lastChangeCount = pasteboard.changeCount
        lastContentHash = getClipboardContentHash()
        
        // Start high-frequency timer-based monitoring (polling every 0.05 seconds for ultra-fast response)
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkClipboardChanges()
        }
        
        // Set timer to high priority for better responsiveness
        if let timer = monitoringTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
        
        // Also listen for app activation events to check immediately when switching apps
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Immediate check when app becomes active
            self?.checkClipboardChanges()
        }
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)
        
        // Phase 3: Remove handoff notification observers
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("NSApplicationWillContinueUserActivityNotification"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("NSApplicationDidContinueUserActivityNotification"), object: nil)
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
        
        // Get content hash for additional validation
        let currentContentHash = getClipboardContentHash()
        
        // Double-check to avoid processing the same content multiple times
        guard currentContentHash != lastContentHash else {
            lastChangeCount = currentChangeCount
            return
        }
        
        lastChangeCount = currentChangeCount
        lastContentHash = currentContentHash
        handleClipboardChange()
    }
    
    private func getClipboardContentHash() -> Int {
        // Quick hash of clipboard content to detect actual changes
        var hasher = Hasher()
        
        // Hash the most common types quickly
        if let string = pasteboard.string(forType: .string) {
            hasher.combine(string)
        }
        if let url = pasteboard.string(forType: .URL) {
            hasher.combine(url)
        }
        if let data = pasteboard.data(forType: .png) {
            hasher.combine(data.count) // Use data size for images to avoid processing large data
        }
        
        return hasher.finalize()
    }
    
    private func handleClipboardChange() {
        // Process clipboard changes on a background queue to avoid blocking the timer
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Get clipboard content
            guard let clipboardContent = self.checkClipboardContent() else {
                return
            }
            
            // Skip if this change was made by our app
            if self.shouldIgnoreClipboardChange(content: clipboardContent.content) {
                print("Ignoring clipboard change made by this app: \(clipboardContent.content.prefix(30))")
                return
            }
            
            // Phase 3: Detect if this is Universal Handoff data
            let isHandoffData = self.isUniversalHandoffData()
            let sourceAppInfo: SourceAppInfo
            
            if isHandoffData {
                print("🔄 [MacBook Relay] Universal Handoff detected - iPhone → MacBook relay")
                // For handoff data, we know it came from iPhone
                sourceAppInfo = SourceAppInfo(
                    bundleID: "com.apple.universalhandoff.iphone", 
                    name: "iPhone (Handoff)",
                    iconData: nil
                )
            } else {
                // Detect source application for local clipboard changes
                sourceAppInfo = self.sourceAppDetector.detectCurrentApp()
            }
            
            // Check for privacy restrictions
            let privacyCheck = self.privacyFilter.shouldExcludeContent(
                clipboardContent.content,
                contentType: clipboardContent.type,
                sourceApp: sourceAppInfo.bundleID
            )
            
            if privacyCheck.shouldExclude {
                return
            }
            
            // Phase 3: Save with relay metadata
            self.saveClipboardItem(
                content: clipboardContent.content,
                type: clipboardContent.type,
                sourceApp: sourceAppInfo.bundleID,
                sourceAppName: sourceAppInfo.name,
                sourceAppIcon: sourceAppInfo.iconData,
                isHandoffRelay: isHandoffData
            )
            
            // Update published properties on main queue
            DispatchQueue.main.async {
                self.lastClipboardContent = clipboardContent.content
                self.clipboardDidChange.toggle() // Trigger UI refresh
            }
        }
    }
    
    private func checkClipboardContent() -> ClipboardContent? {
        let pasteboard = NSPasteboard.general
        
        // 1. First priority: Get original image data in native format
        let imageTypes = [
            NSPasteboard.PasteboardType.png,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.jpg"), 
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("public.heif"),
            NSPasteboard.PasteboardType("public.gif"),
            NSPasteboard.PasteboardType("public.bmp"),
            NSPasteboard.PasteboardType("public.webp"),
            NSPasteboard.PasteboardType("public.svg-image")
        ]
        
        // Try to get original image data first
        for imageType in imageTypes {
            if let imageData = pasteboard.data(forType: imageType) {
                // Verify it's valid image data
                if let _ = NSImage(data: imageData) {
                    let base64String = imageData.base64EncodedString()
                    return ClipboardContent(content: base64String, type: .image)
                }
            }
        }
        
        // 2. Check for file URLs that might be images
        if let fileURL = pasteboard.string(forType: .fileURL) {
            if let url = URL(string: fileURL) {
                // Check if it's an image file and try to read it directly
                if isImageFile(fileURL) || hasImageUTI(url) {
                    do {
                        // Read the actual image file from disk
                        let imageData = try Data(contentsOf: url)
                        
                        // Verify it's actually image data by trying to create NSImage
                        if let _ = NSImage(data: imageData) {
                            let base64String = imageData.base64EncodedString()
                            return ClipboardContent(content: base64String, type: .image)
                        }
                    } catch {
                        // Failed to read image file, continue to other content types
                    }
                }
            }
        }
        
        // 3. Check for TIFF data (fallback for other image sources)
        if let tiffData = pasteboard.data(forType: .tiff) {
            // Only accept larger TIFF files to avoid file icons
            if tiffData.count > 100000, let _ = NSImage(data: tiffData) {
                let base64String = tiffData.base64EncodedString()
                return ClipboardContent(content: base64String, type: .image)
            }
        }
        
        // 4. Check for URLs
        if let urlString = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string) {
            if isValidURL(urlString) {
                return ClipboardContent(content: urlString, type: .url)
            }
        }
        
        // 5. Check for text
        if let text = pasteboard.string(forType: .string) {
            if isValidURL(text) {
                return ClipboardContent(content: text, type: .url)
            } else {
                return ClipboardContent(content: text, type: .text)
            }
        }
        
        return nil
    }
    
    // MARK: - Phase 3: Universal Handoff Detection
    
    private func isUniversalHandoffData() -> Bool {
        // Check if clipboard change occurred within handoff detection window
        if let handoffTime = lastHandoffDetectionTime,
           Date().timeIntervalSince(handoffTime) <= handoffDetectionWindow {
            return true
        }
        
        // Additional heuristics for handoff detection
        return detectHandoffHeuristics()
    }
    
    private func detectHandoffHeuristics() -> Bool {
        let pasteboard = NSPasteboard.general
        
        // Check for handoff-specific pasteboard properties
        // Universal Handoff often includes specific pasteboard types or metadata
        let pasteboardTypes = pasteboard.types ?? []
        
        // Look for handoff-specific types or patterns
        let handoffIndicators = [
            "com.apple.handoff.clipboard",
            "com.apple.uikit.pasteboard",
            "public.utf8-plain-text" // with specific patterns
        ]
        
        for type in pasteboardTypes {
            if handoffIndicators.contains(type.rawValue) {
                return true
            }
        }
        
        // Check for timing patterns typical of handoff
        let timeSinceLastChange = Date().timeIntervalSince(lastHandoffDetectionTime ?? Date.distantPast)
        if timeSinceLastChange < 3.0 && timeSinceLastChange > 0.1 {
            // If clipboard changed shortly after potential handoff preparation
            return true
        }
        
        return false
    }
    
    // MARK: - Helper Methods
    
    private func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return url.scheme != nil && (url.scheme == "http" || url.scheme == "https")
    }
    
    private func isImageFile(_ path: String) -> Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "heif", "webp", "svg"]
        let pathExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        return imageExtensions.contains(pathExtension)
    }
    
    private func hasImageUTI(_ url: URL) -> Bool {
        guard let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier else {
            return false
        }
        return UTType(uti)?.conforms(to: .image) == true
    }
    
    private func saveClipboardItem(content: String, type: ContentType, sourceApp: String?, sourceAppName: String?, sourceAppIcon: Data?, isHandoffRelay: Bool = false) {
        // Phase 3: Create clipboard item with relay metadata
        let clipboardItem = dataManager.createClipboardItem(
            content: content,
            contentType: type,
            sourceApp: sourceApp,
            sourceAppName: sourceAppName,
            sourceAppIcon: sourceAppIcon
        )
        
        // Phase 3: Set relay metadata if this is handoff data
        if isHandoffRelay {
            let deviceIdentifier = ContentHashingUtility.getDeviceIdentifier()
            clipboardItem.relayedBy = deviceIdentifier
            clipboardItem.createdOnDevice = "iPhone" // We know handoff comes from iPhone
            print("🔄 [MacBook Relay] Item marked as relayed from iPhone: \(clipboardItem.id?.uuidString ?? "unknown")")
        }
        
        // Phase 5: Enhanced MacBook relay with offline fallback
        print("📤 [MacBook Relay] Processing clipboard item...")
        dataManager.saveContext() // Save first to ensure Core Data integrity
        
        // Phase 5: Try iCloud push first, with offline queue fallback
        Task {
            await handleClipboardSync(clipboardItem, content: content, isHandoffRelay: isHandoffRelay)
        }
    }
    
    // MARK: - Phase 5: Enhanced Sync with Offline Fallback
    
    private func handleClipboardSync(_ clipboardItem: ClipboardItem, content: String, isHandoffRelay: Bool) async {
        do {
            // Try to push to iCloud
            try await dataManager.cloudKitManager.pushItem(clipboardItem)
            print("✅ [MacBook Relay] Successfully pushed to iCloud: \(content.prefix(30))")
            
            // If this was a handoff relay and iCloud succeeded, mark it
            if isHandoffRelay {
                print("🔄 [MacBook Relay] Successfully relayed handoff item to iCloud")
            }
            
        } catch {
            print("❌ [MacBook Relay] iCloud push failed: \(error)")
            
            // Phase 5: Offline fallback - the operation is already queued by CloudKitManager
            // But we can enhance handoff support for immediate cross-device sharing
            if isHandoffRelay {
                print("🔄 [Offline Fallback] Handoff item will be queued until online")
            } else {
                // For local items, we could implement enhanced Universal Handoff broadcasting
                await handleOfflineFallback(content: content, type: ContentType(rawValue: clipboardItem.contentType ?? "") ?? .text)
            }
        }
    }
    
    private func handleOfflineFallback(content: String, type: ContentType) async {
        // Phase 5: When offline, MacBook can still act as Universal Handoff broadcaster
        print("📡 [Offline Fallback] Broadcasting via Universal Handoff while offline")
        
        // Create a handoff activity to broadcast the clipboard content
        let handoffActivity = NSUserActivity(activityType: "com.wanmenzy.kopi.macbook.clipboard")
        handoffActivity.title = "Kopi Clipboard (MacBook)"
        handoffActivity.isEligibleForHandoff = true
        handoffActivity.isEligibleForSearch = false
        handoffActivity.webpageURL = nil
        
        // Include clipboard data in handoff
        handoffActivity.userInfo = [
            "clipboard_content": content,
            "clipboard_type": type.rawValue,
            "device_id": ContentHashingUtility.getDeviceIdentifier(),
            "timestamp": Date().timeIntervalSince1970,
            "offline_fallback": true
        ]
        
        handoffActivity.needsSave = true
        handoffActivity.becomeCurrent()
        
        print("📡 [Offline Fallback] MacBook broadcasting clipboard via Universal Handoff")
        
        // Keep the activity current for a reasonable time to allow pickup
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            handoffActivity.resignCurrent()
        }
    }
    
    // MARK: - App Copy Tracking
    
    // Call this method when the app copies something to the clipboard
    // This helps avoid detecting our own clipboard changes
    func notifyAppCopiedToClipboard(content: String) {
        lastAppCopyContent = content
        lastAppCopyTime = Date()
        print("App copied to clipboard: \(content.prefix(30))")
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