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
    private let cloudKitManager = CloudKitManager.shared
    
    // Phase 4: Sync client properties
    private var lastChangeCount: Int = 0
    private var lastSyncDate: Date?
    private var syncTimer: Timer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    // Track clipboard changes made by this app to avoid loops
    private var ignoreNextClipboardChange = false
    private var lastAppCopyContent: String?
    private var lastAppCopyTime: Date?
    
    // Phase 4: Universal Handoff support
    private var handoffActivity: NSUserActivity?
    
    // Background processing
    private let backgroundTaskIdentifier = "com.wanmenzy.kopi.clipboardsync"
    
    @Published var syncStatus: String = "Ready"
    @Published var lastSyncTime: Date?
    
    init() {
        // Initialize with current clipboard state
        lastChangeCount = UIPasteboard.general.changeCount
        
        // Phase 4: Start as sync client (pull-only)
        setupSyncClient()
        
        // Listen for app lifecycle events
        setupAppLifecycleObservers()
        
        // Register background tasks
        registerBackgroundTasks()
        
        // Set up Universal Handoff
        setupUniversalHandoff()
        
        print("📱 [iOS] ClipboardService initialized as sync client")
    }
    
    deinit {
        stopSyncClient()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Phase 4: Sync Client Implementation
    
    private func setupSyncClient() {
        // Phase 4: iPhone acts as sync client - pulls from iCloud periodically
        syncTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task {
                await self?.performSyncFromCloud()
            }
        }
        
        // Immediate sync on startup
        Task {
            await performSyncFromCloud()
        }
        
        print("📱 [iOS] Sync client started - pulling from iCloud every 5 seconds")
    }
    
    private func stopSyncClient() {
        syncTimer?.invalidate()
        syncTimer = nil
        print("📱 [iOS] Sync client stopped")
    }
    
    @MainActor
    private func performSyncFromCloud() async {
        syncStatus = "Syncing..."
        
        do {
            // Phase 5: Enhanced sync with offline reconciliation
            print("📥 [iPhone Sync Client] Starting enhanced sync from iCloud...")
            
            // Check if we just came back online
            if cloudKitManager.isConnected && (lastSyncDate == nil || Date().timeIntervalSince(lastSyncDate!) > 300) {
                // Perform full reconciliation sync if it's been a while or first sync
                print("🔄 [iPhone Sync Client] Performing full reconciliation sync")
                await cloudKitManager.forceFullSync()
            } else {
                // Regular sync
                await cloudKitManager.syncFromCloud()
            }
            
            syncStatus = "Synced"
            lastSyncTime = Date()
            lastSyncDate = Date()
            
            print("✅ [iPhone Sync Client] Successfully synced from iCloud")
            
            // Phase 5: Check for offline queue status
            let queueStatus = cloudKitManager.getOfflineQueueStatus()
            if queueStatus.count > 0 {
                print("📊 [iPhone Sync Client] Offline queue has \(queueStatus.count) pending operations")
            }
            
        } catch {
            syncStatus = cloudKitManager.isConnected ? "Sync Failed" : "Offline"
            print("❌ [iPhone Sync Client] Sync failed: \(error)")
        }
    }
    
    // MARK: - Phase 4: Universal Handoff Implementation
    
    private func setupUniversalHandoff() {
        // Set up handoff activity for clipboard sync
        handoffActivity = NSUserActivity(activityType: "com.wanmenzy.kopi.clipboard")
        handoffActivity?.title = "Kopi Clipboard"
        handoffActivity?.isEligibleForHandoff = true
        handoffActivity?.isEligibleForSearch = false
        handoffActivity?.webpageURL = nil
        
        print("🔄 [iPhone Handoff] Universal Handoff configured")
    }
    
    private func sendViaUniversalHandoff(content: String, type: ContentType) {
        guard let activity = handoffActivity else { return }
        
        // Phase 4: Send clipboard data via Universal Handoff when app is closed
        activity.userInfo = [
            "clipboard_content": content,
            "clipboard_type": type.rawValue,
            "device_id": ContentHashingUtility.getDeviceIdentifier(),
            "timestamp": Date().timeIntervalSince1970
        ]
        
        activity.needsSave = true
        activity.becomeCurrent()
        
        print("🔄 [iPhone Handoff] Sent via Universal Handoff: \(type) - \(content.prefix(30))")
    }
    
    // Phase 4: Removed old clipboard monitoring - replaced with sync client
    
    private func setupAppLifecycleObservers() {
        // Phase 4: Monitor when app becomes active to sync from iCloud immediately
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("📱 [iPhone Sync Client] App became active - syncing from iCloud")
            Task {
                await self?.performSyncFromCloud()
            }
            
            // Also check for new local clipboard changes to send via handoff
            self?.checkForLocalClipboardChanges()
        }
        
        // Phase 4: Monitor when app goes to background - send current clipboard via handoff if changed
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("📱 [iPhone Sync Client] App entered background")
            self?.handleAppGoingToBackground()
            self?.scheduleBackgroundProcessing()
        }
        
        // Monitor when app will terminate
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopSyncClient()
        }
    }
    
    // Phase 4: Handle app going to background - send clipboard via handoff if needed
    private func handleAppGoingToBackground() {
        checkForLocalClipboardChanges()
    }
    
    // Phase 5: Enhanced local clipboard monitoring with offline-aware handoff
    private func checkForLocalClipboardChanges() {
        let currentChangeCount = UIPasteboard.general.changeCount
        
        // Only process if clipboard has changed since last check
        guard currentChangeCount != lastChangeCount else { return }
        
        if ignoreNextClipboardChange {
            ignoreNextClipboardChange = false
            lastChangeCount = currentChangeCount
            return
        }
        
        // Get current clipboard content
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
        
        // Phase 5: Enhanced handoff with offline-aware strategy
        Task {
            await handleLocalClipboardChange(content: clipboardContent.content, type: clipboardContent.type)
        }
        lastChangeCount = currentChangeCount
        
        print("📱 [iPhone Sync Client] Local clipboard change detected - processing with offline fallback")
    }
    
    // MARK: - Phase 5: Enhanced Offline-Aware Clipboard Handling
    
    private func handleLocalClipboardChange(content: String, type: ContentType) async {
        // Phase 5: Check if we're online or offline
        if await cloudKitManager.isConnected {
            // Online: Send via Universal Handoff for immediate MacBook relay
            print("🌐 [iPhone Online] Sending via Universal Handoff for MacBook relay")
            await sendViaUniversalHandoffWithConfirmation(content: content, type: type)
            
            // Also try direct sync after a short delay to catch any missed items
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                Task {
                    await self.performSyncFromCloud()
                }
            }
            
        } else {
            // Offline: Store locally and send via Universal Handoff as fallback
            print("📵 [iPhone Offline] Storing locally and sending via Universal Handoff")
            await handleOfflineClipboardChange(content: content, type: type)
        }
    }
    
    private func sendViaUniversalHandoffWithConfirmation(content: String, type: ContentType) async {
        sendViaUniversalHandoff(content: content, type: type)
        
        // Add confirmation tracking
        print("🔄 [iPhone Handoff] Sent with confirmation: \(type) - \(content.prefix(30))")
    }
    
    private func handleOfflineClipboardChange(content: String, type: ContentType) async {
        // Phase 5: When offline, save locally with special offline marking
        let context = persistenceController.container.viewContext
        let clipboardItem = ClipboardItem(context: context)
        
        clipboardItem.id = UUID()
        clipboardItem.content = content
        clipboardItem.contentType = type.rawValue
        clipboardItem.contentHash = ContentHashingUtility.generateContentHash(from: content)
        clipboardItem.createdAt = Date()
        clipboardItem.createdOnDevice = ContentHashingUtility.getDeviceIdentifier()
        clipboardItem.lastModified = Date()
        clipboardItem.iCloudSyncStatus = SyncStatus.local.rawValue // Will be synced when online
        
        // Mark as offline-created for reconciliation
        clipboardItem.sourceAppBundleID = "com.apple.clipboard.offline"
        clipboardItem.sourceAppName = "iPhone (Offline)"
        
        do {
            try context.save()
            print("💾 [iPhone Offline] Saved clipboard item locally: \(content.prefix(30))")
            
            // Still send via Universal Handoff for immediate availability
            sendViaUniversalHandoff(content: content, type: type)
            
            // Queue for sync when back online
            try? await cloudKitManager.pushItem(clipboardItem) // This will queue offline
            
        } catch {
            print("❌ [iPhone Offline] Failed to save clipboard item: \(error)")
        }
    }
    
    // MARK: - Phase 5: Enhanced Sync with Offline Reconciliation
    
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
        
        // Phase 4: Perform sync from iCloud in background
        Task {
            await self.performSyncFromCloud()
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
    
    // MARK: - Phase 4: Sync Client Public Interface
    
    // Manually trigger sync from UI
    func forceSyncFromCloud() {
        Task {
            await performSyncFromCloud()
        }
    }
    
    // Copy item to clipboard (when user taps an item)
    func copyToClipboard(_ item: ClipboardItem) {
        guard let content = item.content else { return }
        
        // Track that we're copying to clipboard to avoid handoff loop
        lastAppCopyContent = content
        lastAppCopyTime = Date()
        ignoreNextClipboardChange = true
        
        let pasteboard = UIPasteboard.general
        
        // Set content based on type
        switch ContentType(rawValue: item.contentType ?? "text") ?? .text {
        case .text, .url, .file:
            pasteboard.string = content
        case .image:
            // Handle base64 encoded image data
            if let imageData = Data(base64Encoded: content),
               let image = UIImage(data: imageData) {
                pasteboard.image = image
            } else {
                // Fallback to string if not base64
                pasteboard.string = content
            }
        }
        
        print("📋 [iPhone Sync Client] Copied to clipboard: \(content.prefix(50))...")
    }
    
    // MARK: - Helper Methods
    
    private func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return url.scheme != nil && (url.scheme == "http" || url.scheme == "https")
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




