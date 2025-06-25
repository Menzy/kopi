//
//  ClipboardDataManager.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import Foundation
import CoreData
import CloudKit
import AppKit

@MainActor
class ClipboardDataManager: ObservableObject {
    static let shared = ClipboardDataManager()
    
    private let persistenceController = PersistenceController.shared
    let cloudKitManager: CloudKitManager
    
    private var viewContext: NSManagedObjectContext {
        persistenceController.container.viewContext
    }
    
    private init() {
        cloudKitManager = CloudKitManager.shared
    }
    
    // MARK: - CRUD Operations
    
    func createClipboardItem(
        content: String,
        contentType: ContentType,
        sourceApp: String? = nil,
        sourceAppName: String? = nil,
        sourceAppIcon: Data? = nil
    ) -> ClipboardItem {
        // Generate content hash first for deduplication
        let contentHash = ContentHashingUtility.generateContentHash(from: content)
        
        // Check if we already have an item with this exact content hash
        if let existingItem = findItemByContentHash(contentHash) {
            print("🔍 [macOS Dedup] Found existing item with same content hash: \(existingItem.id?.uuidString ?? "unknown") - content: \(content.prefix(30))")
            print("🔍 [macOS Dedup] SKIPPING creation of duplicate item - updating timestamp instead")
            // Update the existing item's timestamp to move it to the top
            existingItem.lastModified = Date()
            saveContext()
            
            // Post notification to update all views
            NotificationCenter.default.post(name: .cloudKitSyncCompleted, object: nil)
            
            return existingItem
        }
        
        let item = ClipboardItem(context: viewContext)
        item.id = UUID()
        item.content = content
        item.contentType = contentType.rawValue
        // contentPreview removed in new schema
        item.createdAt = Date()
        item.lastModified = Date()
        item.contentHash = contentHash
        item.iCloudSyncStatus = SyncStatus.local.rawValue
        item.createdOnDevice = ContentHashingUtility.getDeviceIdentifier()
        item.sourceAppBundleID = sourceApp
        item.sourceAppName = sourceAppName
        item.sourceAppIcon = sourceAppIcon
        // fileSize removed in new schema

        item.markedAsDeleted = false
        // isSensitive removed in new schema
        
        let itemId = item.id?.uuidString ?? "unknown"
        print("➕ [macOS] Creating NEW clipboard item: \(itemId) - \(content.prefix(50))")
        
        saveContext()
        
        // Post notification to update all views immediately
        NotificationCenter.default.post(name: .cloudKitSyncCompleted, object: nil)
        
        // MacBook acts as relay - push to CloudKit immediately
        Task {
            do {
                try await cloudKitManager.pushItem(item)
                print("✅ [MacBook Relay] Item pushed to iCloud: \(itemId)")
            } catch {
                print("❌ [MacBook Relay] Failed to push to iCloud: \(error)")
            }
        }
        
        return item
    }
    
    func fetchAllClipboardItems() -> [ClipboardItem] {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)]
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("Error fetching clipboard items: \(error)")
            return []
        }
    }
    
    func fetchRecentClipboardItems(limit: Int = 50) -> [ClipboardItem] {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)]
        request.fetchLimit = limit
        request.predicate = NSPredicate(format: "markedAsDeleted == NO")
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("Error fetching recent clipboard items: \(error)")
            return []
        }
    }
    
    func deleteClipboardItem(_ item: ClipboardItem) {
        let itemId = item.id?.uuidString ?? "unknown"
        let content = item.content?.prefix(50) ?? "no content"
        print("🗑️ [macOS] Deleting clipboard item: \(itemId) - \(content)")
        
        // Capture the object ID before any modifications
        let objectID = item.objectID
        
        // Soft delete in CloudKit (mark as deleted)
        item.markedAsDeleted = true
        item.lastModified = Date()
        
        // Save the changes to persist the markedAsDeleted flag
        saveContext()
        
        // Delete from CloudKit first, then delete locally
        Task {
            do {
                // Use the direct CloudKit delete API instead of pushItem
                if let itemUUID = item.id {
                    try await cloudKitManager.deleteItem(id: itemUUID)
                    print("✅ [MacBook Relay] Deletion synced to iCloud: \(itemId)")
                } else {
                    print("❌ [MacBook Relay] Cannot delete - item missing ID: \(itemId)")
                    throw CloudKitError.invalidData("Item missing ID")
                }
                
                // Only delete locally after successful CloudKit sync
                await MainActor.run {
                    do {
                        let itemToDelete = try self.viewContext.existingObject(with: objectID) as? ClipboardItem
                        if let itemToDelete = itemToDelete {
                            self.viewContext.delete(itemToDelete)
                            self.saveContext()
                            print("✅ [macOS] Item deleted locally after CloudKit sync: \(itemId)")
                            
                            // Post notification to refresh UI
                            NotificationCenter.default.post(name: .cloudKitSyncCompleted, object: nil)
                        }
                    } catch {
                        print("❌ [macOS] Failed to delete item locally: \(error)")
                    }
                }
            } catch {
                print("❌ [MacBook Relay] Failed to sync deletion: \(error)")
                // Still delete locally even if CloudKit sync fails
                await MainActor.run {
                    do {
                        let itemToDelete = try self.viewContext.existingObject(with: objectID) as? ClipboardItem
                        if let itemToDelete = itemToDelete {
                            self.viewContext.delete(itemToDelete)
                            self.saveContext()
                            print("⚠️ [macOS] Item deleted locally despite CloudKit sync failure: \(itemId)")
                            
                            // Post notification to refresh UI
                            NotificationCenter.default.post(name: .cloudKitSyncCompleted, object: nil)
                        }
                    } catch {
                        print("❌ [macOS] Failed to delete item locally: \(error)")
                    }
                }
            }
        }
    }
    
    func deleteClipboardItems(_ items: [ClipboardItem]) {
        print("🗑️ [macOS] Batch deleting \(items.count) clipboard items")
        
        // Capture object IDs and item info before any modifications
        let itemsInfo = items.map { item in
            return (
                objectID: item.objectID,
                itemId: item.id?.uuidString ?? "unknown",
                content: item.content?.prefix(30) ?? "no content"
            )
        }
        
        // First mark all as deleted
        for item in items {
            item.markedAsDeleted = true
            item.lastModified = Date()
        }
        
        // Save the changes to persist the markedAsDeleted flags
        saveContext()
        
        // Then delete from CloudKit and delete locally
        Task {
            var syncedCount = 0
            var failedCount = 0
            
            for (index, item) in items.enumerated() {
                let info = itemsInfo[index]
                print("   - Deleting: \(info.itemId) - \(info.content)")
                
                do {
                    // Use the direct CloudKit delete API instead of pushItem
                    if let itemUUID = item.id {
                        try await cloudKitManager.deleteItem(id: itemUUID)
                        print("     ✅ [MacBook Relay] Deletion synced: \(info.itemId)")
                        syncedCount += 1
                    } else {
                        print("     ❌ [MacBook Relay] Cannot delete - item missing ID: \(info.itemId)")
                        failedCount += 1
                    }
                } catch {
                    print("     ❌ [MacBook Relay] Failed to sync deletion: \(error)")
                    failedCount += 1
                }
            }
            
            // Delete all items locally after CloudKit sync attempts
            await MainActor.run {
                for info in itemsInfo {
                    do {
                        let itemToDelete = try self.viewContext.existingObject(with: info.objectID) as? ClipboardItem
                        if let itemToDelete = itemToDelete {
                            self.viewContext.delete(itemToDelete)
                        }
                    } catch {
                        print("❌ [macOS] Failed to delete item locally: \(info.itemId) - \(error)")
                    }
                }
                self.saveContext()
                
                print("✅ [macOS] Batch deletion completed for \(items.count) items - CloudKit synced: \(syncedCount), failed: \(failedCount)")
                
                // Post notification to refresh UI
                NotificationCenter.default.post(name: .cloudKitSyncCompleted, object: nil)
            }
        }
    }
    

    
    func markAsSensitive(_ item: ClipboardItem) {
        // isSensitive removed in new schema - functionality deprecated
        saveContext()
    }
    
    func updateClipboardItem(_ item: ClipboardItem, content: String) {
        item.content = content
        item.lastModified = Date()
        // contentPreview removed in new schema
        // fileSize removed in new schema
        saveContext()
        
        // Post notification to update all views
        NotificationCenter.default.post(name: .cloudKitSyncCompleted, object: nil)
    }
    
    // MARK: - Enhanced Query Methods
    
    func getRecentItems(limit: Int = 50) -> [ClipboardItem] {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.predicate = NSPredicate(format: "markedAsDeleted == NO")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)]
        request.fetchLimit = limit
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch recent items: \(error)")
            return []
        }
    }
    
    func getAvailableApps() -> [String] {
        let request: NSFetchRequest<NSFetchRequestResult> = ClipboardItem.fetchRequest()
        request.predicate = NSPredicate(format: "markedAsDeleted == NO AND sourceAppName != nil")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["sourceAppName"]
        request.returnsDistinctResults = true
        
        do {
            let results = try viewContext.fetch(request) as? [[String: Any]] ?? []
            return results.compactMap { $0["sourceAppName"] as? String }.sorted()
        } catch {
            print("❌ Failed to fetch available apps: \(error)")
            return []
        }
    }
    
    func searchItems(
        searchText: String? = nil,
        contentType: ContentType? = nil,
        sourceApp: String? = nil,

    ) -> [ClipboardItem] {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        
        var predicates: [NSPredicate] = [NSPredicate(format: "markedAsDeleted == NO")]
        
        // Search text
        if let searchText = searchText, !searchText.isEmpty {
            predicates.append(NSPredicate(format: "content CONTAINS[cd] %@", searchText))
        }
        
        // Content type filter
        if let contentType = contentType {
            predicates.append(NSPredicate(format: "contentType == %@", contentType.rawValue))
        }
        
        // Source app filter
        if let sourceApp = sourceApp {
            predicates.append(NSPredicate(format: "sourceAppName == %@", sourceApp))
        }
        

        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        // Always sort by newest first
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)]
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("❌ Failed to search items: \(error)")
            return []
        }
    }
    
    func copyToClipboard(_ item: ClipboardItem) {
        guard let content = item.content else { return }
        
        // Notify clipboard monitor before copying to avoid loop
        ClipboardMonitor.shared.notifyAppCopiedToClipboard(content: content)
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        // Set content based on type
        switch ContentType(rawValue: item.contentType ?? "text") ?? .text {
        case .text, .url, .file:
            pasteboard.setString(content, forType: .string)
        case .image:
            // Handle base64 encoded image data
            if let imageData = Data(base64Encoded: content) {
                pasteboard.setData(imageData, forType: .tiff)
            } else {
                // Fallback to string if not base64
                pasteboard.setString(content, forType: .string)
            }
        }
        
        print("📋 Copied to clipboard: \(content.prefix(50))...")
    }
    
    // MARK: - Phase 3: Relay System Methods
    
    func getRelayedItems() -> [ClipboardItem] {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.predicate = NSPredicate(format: "markedAsDeleted == NO AND relayedBy != nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)]
        
        do {
            let items = try viewContext.fetch(request)
            print("📊 [MacBook Relay] Found \(items.count) relayed items")
            return items
        } catch {
            print("❌ Failed to fetch relayed items: \(error)")
            return []
        }
    }
    
    func getLocalItems() -> [ClipboardItem] {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.predicate = NSPredicate(format: "markedAsDeleted == NO AND relayedBy == nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)]
        
        do {
            let items = try viewContext.fetch(request)
            print("📊 [MacBook Relay] Found \(items.count) local items")
            return items
        } catch {
            print("❌ Failed to fetch local items: \(error)")
            return []
        }
    }
    
    func getRelayStatistics() -> RelayStatistics {
        let totalItems = getRecentItems(limit: 1000).count
        let relayedItems = getRelayedItems().count
        let localItems = getLocalItems().count
        
        return RelayStatistics(
            totalItems: totalItems,
            relayedItems: relayedItems,
            localItems: localItems,
            relayPercentage: totalItems > 0 ? Double(relayedItems) / Double(totalItems) * 100 : 0
        )
    }
    
    // MARK: - App Statistics
    
    func getAppStatistics() -> [AppInfo] {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.predicate = NSPredicate(format: "markedAsDeleted == NO")
        
        do {
            let items = try viewContext.fetch(request)
            
            // Group by bundle ID and count items
            let groupedItems = Dictionary(grouping: items) { item in
                item.sourceAppBundleID ?? "unknown"
            }
            
            let appInfos = groupedItems.compactMap { (bundleID, items) -> AppInfo? in
                guard let firstItem = items.first else { return nil }
                
                return AppInfo(
                    bundleID: bundleID,
                    name: firstItem.sourceAppName ?? "Unknown App",
                    iconData: firstItem.sourceAppIcon,
                    itemCount: items.count
                )
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } // Sort alphabetically by name
            
            return appInfos
        } catch {
            print("Failed to fetch app statistics: \(error)")
            return []
        }
    }
    
    func getTotalItemCount() -> Int {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.predicate = NSPredicate(format: "markedAsDeleted == NO")
        
        do {
            return try viewContext.count(for: request)
        } catch {
            print("Failed to get total item count: \(error)")
            return 0
        }
    }
    
    // MARK: - Helper Methods
    
    func saveContext() {
        do {
            try viewContext.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }
    
    private func createPreview(from content: String, type: ContentType) -> String {
        let maxLength = 100
        if content.count <= maxLength {
            return content
        }
        return String(content.prefix(maxLength)) + "..."
    }
    
    private func getDeviceIdentifier() -> String {
        #if os(macOS)
        return "macOS"
        #elseif os(iOS)
        return "iOS"
        #else
        return "Unknown"
        #endif
    }
    
    private func findItemByContentHash(_ contentHash: String) -> ClipboardItem? {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.predicate = NSPredicate(format: "contentHash == %@ AND markedAsDeleted == NO", contentHash)
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.lastModified, ascending: false)]
        
        do {
            return try viewContext.fetch(request).first
        } catch {
            print("❌ [macOS Dedup] Error finding item by content hash: \(error)")
            return nil
        }
    }
} 