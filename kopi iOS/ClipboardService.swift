//
//  ClipboardService.swift
//  kopi iOS
//
//  Created by Wan Menzy on 20/06/2025.
//

import Foundation
import UIKit
import CoreData

class ClipboardService: ObservableObject {
    private let persistenceController = PersistenceController.shared
    private var lastChangeCount: Int = 0
    private var timer: Timer?
    
    // Track clipboard changes made by this app to avoid loops
    private var ignoreNextClipboardChange = false
    private var lastAppCopyContent: String?
    private var lastAppCopyTime: Date?
    
    init() {
        lastChangeCount = UIPasteboard.general.changeCount
        
        // Check clipboard every 2 seconds (iOS limitations)
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func checkClipboard() {
        let currentChangeCount = UIPasteboard.general.changeCount
        
        // Only process if pasteboard has changed
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount
        
        // Get clipboard content
        guard let content = UIPasteboard.general.string,
              !content.isEmpty else { return }
        
        // Skip if this change was made by our app
        if shouldIgnoreClipboardChange(content: content) {
            print("Ignoring clipboard change made by this app: \(content.prefix(30))")
            return
        }
        
        // Check if we already have this exact content from recently
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.predicate = NSPredicate(format: "content == %@", content)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.timestamp, ascending: false)]
        request.fetchLimit = 1
        
        do {
            let existingItems = try context.fetch(request)
            
            // If we have the same content from less than 30 seconds ago, skip
            if let existing = existingItems.first,
               let timestamp = existing.timestamp,
               Date().timeIntervalSince(timestamp) < 30 {
                print("Skipping duplicate content from \(Date().timeIntervalSince(timestamp)) seconds ago")
                return
            }
        } catch {
            print("Error checking for existing clipboard items: \(error)")
        }
        
        // Save new clipboard item
        saveClipboardItem(content: content)
    }
    
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
    
    private func saveClipboardItem(content: String) {
        let context = persistenceController.container.viewContext
        
        let item = ClipboardItem(context: context)
        item.id = UUID()
        item.content = content
        item.contentPreview = content.count > 50 ? String(content.prefix(50)) + "..." : content
        item.timestamp = Date()
        item.deviceOrigin = "iOS"
        item.isTransient = false
        item.isSensitive = false
        item.isPinned = false
        item.fileSize = Int64(content.data(using: .utf8)?.count ?? 0)
        
        // Determine content type
        if let url = URL(string: content), url.scheme != nil {
            item.contentType = ContentType.url.rawValue
        } else {
            item.contentType = ContentType.text.rawValue
        }
        
        // Try to get source app (limited on iOS)
        item.sourceApp = Bundle.main.bundleIdentifier
        item.sourceAppName = "iOS App"
        
        let itemId = item.id?.uuidString ?? "unknown"
        print("➕ [iOS] Creating clipboard item: \(itemId) - \(content.prefix(50))")
        
        do {
            try context.save()
            print("✅ [iOS] Item saved to CloudKit: \(itemId)")
        } catch {
            print("❌ [iOS] Error saving clipboard item: \(error)")
        }
    }
}
