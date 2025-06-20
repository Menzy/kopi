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
        
        // Get clipboard content
        guard let clipboardContent = UIPasteboard.general.string,
              !clipboardContent.isEmpty else {
            lastChangeCount = currentChangeCount
            return
        }
        
        // Skip if this is content we just copied
        if let lastContent = lastAppCopyContent,
           let lastTime = lastAppCopyTime,
           lastContent == clipboardContent,
           Date().timeIntervalSince(lastTime) < 2.0 {
            lastChangeCount = currentChangeCount
            return
        }
        
        // Process the new clipboard content
        saveClipboardItem(content: clipboardContent)
        lastChangeCount = currentChangeCount
        
        print("📋 [iOS] Clipboard changed - saved new item")
    }
    
    private func saveClipboardItem(content: String) {
        let context = persistenceController.container.viewContext
        
        // Check if this content already exists (avoid duplicates)
        let fetchRequest: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "content == %@", content)
        fetchRequest.fetchLimit = 1
        
        do {
            let existingItems = try context.fetch(fetchRequest)
            if !existingItems.isEmpty {
                // Update timestamp of existing item
                existingItems.first?.timestamp = Date()
            } else {
                // Create new clipboard item
                let newItem = ClipboardItem(context: context)
                newItem.id = UUID()
                newItem.content = content
                newItem.timestamp = Date()
                newItem.contentType = ContentType.text.rawValue
                newItem.sourceAppName = "Mac"
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
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let clipboardSyncSuccess = Notification.Name("clipboardSyncSuccess")
    static let clipboardPermissionNeeded = Notification.Name("clipboardPermissionNeeded")
}



