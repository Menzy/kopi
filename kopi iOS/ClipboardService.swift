//
//  ClipboardService.swift
//  kopi iOS
//
//  Created by Wan Menzy on 20/06/2025.
//

import Foundation
import UIKit
import CoreData
import BackgroundTasks
import UniformTypeIdentifiers

class ClipboardService: ObservableObject {
    private let persistenceController = PersistenceController.shared
    private let deviceManager = DeviceManager.shared
    private let correlator = ClipboardCorrelator.shared
    private var lastChangeCount: Int = 0
    private var timer: Timer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    // Track clipboard changes made by this app to avoid loops
    private var ignoreNextClipboardChange = false
    private var lastAppCopyContent: String?
    private var lastAppCopyTime: Date?
    
    // Background processing
    private let backgroundTaskIdentifier = "com.wanmenzy.kopi.clipboardsync"
    
    init() {
        // Initialize with current clipboard state
        lastChangeCount = UIPasteboard.general.changeCount
        
        // Start monitoring
        startClipboardMonitoring()
        
        // Listen for app lifecycle events
        setupAppLifecycleObservers()
        
        // Register background tasks
        registerBackgroundTasks()
    }
    
    deinit {
        stopClipboardMonitoring()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func startClipboardMonitoring() {
        // Monitor clipboard changes every 0.5 seconds for faster detection
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboardChanges()
        }
        
        print("📋 [iOS] Started clipboard monitoring")
    }
    
    private func stopClipboardMonitoring() {
        timer?.invalidate()
        timer = nil
        print("📋 [iOS] Stopped clipboard monitoring")
    }
    
    private func setupAppLifecycleObservers() {
        // Monitor when app becomes active to check clipboard immediately
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("📱 [iOS] App became active - checking clipboard")
            self?.checkClipboardChanges()
        }
        
        // Monitor when app goes to background
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("📱 [iOS] App entered background")
            self?.scheduleBackgroundProcessing()
        }
        
        // Monitor when app will terminate
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopClipboardMonitoring()
        }
    }
    
    private func checkClipboardChanges() {
        let currentChangeCount = UIPasteboard.general.changeCount
        
        // Skip if no changes or if we should ignore the next change
        guard currentChangeCount != lastChangeCount else { return }
        
        if ignoreNextClipboardChange {
            ignoreNextClipboardChange = false
            lastChangeCount = currentChangeCount
            return
        }
        
        // Get clipboard content with proper type detection
        guard let clipboardContent = checkClipboardContent() else {
            lastChangeCount = currentChangeCount
            return
        }
        
        // Skip if this is content we just copied
        if let lastContent = lastAppCopyContent,
           let lastTime = lastAppCopyTime,
           lastContent == clipboardContent.content,
           Date().timeIntervalSince(lastTime) < 2.0 {
            lastChangeCount = currentChangeCount
            return
        }
        
        // Process the new clipboard content
        saveClipboardItem(content: clipboardContent.content, type: clipboardContent.type)
        lastChangeCount = currentChangeCount
        
        print("📋 [iOS] Clipboard changed - saved new item: \(clipboardContent.type)")
    }
    
    private func saveClipboardItem(content: String, type: ContentType) {
        let context = persistenceController.container.viewContext
        
        // Determine sync source - if this appears to be from Universal Clipboard
        let syncSource: SyncSource = deviceManager.detectUniversalClipboardTransfer(content: content, timestamp: Date()) 
            ? .universalClipboard 
            : .localCopy
        
        // Check if this content already exists (avoid duplicates)
        let fetchRequest: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "content == %@", content)
        fetchRequest.fetchLimit = 1
        
        do {
            let existingItems = try context.fetch(fetchRequest)
            if !existingItems.isEmpty {
                // Update timestamp of existing item
                existingItems.first?.timestamp = Date()
                print("📝 [iOS] Updated existing item timestamp")
            } else {
                // Create new clipboard item with enhanced metadata
                let newItem = ClipboardItem(context: context)
                newItem.id = UUID()
                newItem.content = content
                newItem.timestamp = Date()
                newItem.contentType = type.rawValue
                newItem.sourceAppName = syncSource == .universalClipboard ? "Mac" : "iOS"
                
                // Set unified sync properties
                if syncSource == .universalClipboard {
                    // This is likely from Universal Clipboard - mark as temporary
                    // until we can resolve the canonical ID from the originating device
                    newItem.canonicalID = UUID() // Temporary - will be updated later
                    newItem.initiatingDevice = nil // Will be resolved later
                    newItem.isTemporary = true
                } else {
                    // This is a local copy - we are the initiating device
                    newItem.canonicalID = deviceManager.createCanonicalID()
                    newItem.initiatingDevice = deviceManager.getDeviceID()
                    newItem.isTemporary = false
                }
                
                newItem.syncSource = syncSource.rawValue
                
                let canonicalId = newItem.canonicalID?.uuidString ?? "unknown"
                print("➕ [iOS] Creating clipboard item:")
                print("   📍 Canonical ID: \(canonicalId)")
                print("   🔗 Sync Source: \(syncSource.displayName)")
                print("   📱 Device: \(deviceManager.getDeviceID())")
                print("   🔄 Temporary: \(newItem.isTemporary)")
            }
            
            try context.save()
            print("✅ [iOS] Saved clipboard item successfully")
            
        } catch {
            print("❌ [iOS] Error saving clipboard item: \(error)")
        }
    }
    
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { [weak self] task in
            self?.handleBackgroundClipboardSync(task: task as! BGAppRefreshTask)
        }
    }
    
    private func scheduleBackgroundProcessing() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("📱 [iOS] Scheduled background clipboard sync")
        } catch {
            print("❌ [iOS] Could not schedule background task: \(error)")
        }
    }
    
    private func handleBackgroundClipboardSync(task: BGAppRefreshTask) {
        // Schedule next background refresh
        scheduleBackgroundProcessing()
        
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        // Perform clipboard check in background
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.checkClipboardChanges()
            task.setTaskCompleted(success: true)
        }
    }
    
    // MARK: - Content Detection (Simplified)
    
    private func checkClipboardContent() -> ClipboardContent? {
        let pasteboard = UIPasteboard.general
        
        // 1. Check for images first (this handles Mac-synced images)
        if let image = pasteboard.image {
            print("📋 [iOS] Found image in pasteboard")
            if let imageData = image.pngData() {
                let base64String = imageData.base64EncodedString()
                return ClipboardContent(content: base64String, type: .image)
            }
        }
        
        // 2. Check for URLs
        if let url = pasteboard.url {
            print("📋 [iOS] Found URL in pasteboard: \(url.absoluteString)")
            return ClipboardContent(content: url.absoluteString, type: .url)
        }
        
        // 3. Check for text and detect URLs in text
        if let text = pasteboard.string, !text.isEmpty {
            print("📋 [iOS] Found text in pasteboard")
            
            // Check if text is a URL
            if isValidURL(text) {
                return ClipboardContent(content: text, type: .url)
            } else {
                return ClipboardContent(content: text, type: .text)
            }
        }
        
        print("📋 [iOS] No valid content found in pasteboard")
        return nil
    }
    
    // MARK: - Helper Methods
    
    private func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return url.scheme != nil && (url.scheme == "http" || url.scheme == "https")
    }
    
    // MARK: - App Copy Tracking
    
    // Call this method when the app copies something to the clipboard
    // This helps avoid detecting our own clipboard changes
    func notifyAppCopiedToClipboard(content: String, contentType: ContentType = .text) {
        lastAppCopyContent = content
        lastAppCopyTime = Date()
        
        // Register with correlator for Universal Clipboard tracking
        correlator.registerLocalClipboardAction(content: content, contentType: contentType)
        
        print("🍎 [iOS] App copied to clipboard: \(content.prefix(30))")
    }

}

// MARK: - Supporting Types

struct ClipboardContent {
    let content: String
    let type: ContentType
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let clipboardSyncSuccess = Notification.Name("clipboardSyncSuccess")
    static let clipboardPermissionNeeded = Notification.Name("clipboardPermissionNeeded")
}



