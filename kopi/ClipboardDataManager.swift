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
        let item = ClipboardItem(context: viewContext)
        item.id = UUID()
        item.content = content
        item.contentType = contentType.rawValue
        // contentPreview removed in new schema
        item.createdAt = Date()
        item.lastModified = Date()
        item.contentHash = ContentHashingUtility.generateContentHash(from: content)
        item.iCloudSyncStatus = SyncStatus.local.rawValue
        item.createdOnDevice = ContentHashingUtility.getDeviceIdentifier()
        item.sourceAppBundleID = sourceApp
        item.sourceAppName = sourceAppName
        item.sourceAppIcon = sourceAppIcon
        // fileSize removed in new schema

        item.markedAsDeleted = false
        // isSensitive removed in new schema
        
        let itemId = item.id?.uuidString ?? "unknown"
        print("➕ [macOS] Creating clipboard item: \(itemId) - \(content.prefix(50))")
        
        saveContext()
        
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
        
        // Soft delete in CloudKit (mark as deleted)
        item.markedAsDeleted = true
        item.lastModified = Date()
        
        // Push the deletion to CloudKit first
        Task {
            do {
                try await cloudKitManager.pushItem(item)
                print("✅ [MacBook Relay] Deletion synced to iCloud: \(itemId)")
            } catch {
                print("❌ [MacBook Relay] Failed to sync deletion: \(error)")
            }
        }
        
        // Then delete locally
        viewContext.delete(item)
        saveContext()
    }
    
    func deleteClipboardItems(_ items: [ClipboardItem]) {
        print("🗑️ [macOS] Batch deleting \(items.count) clipboard items")
        
        // First mark all as deleted and sync to CloudKit
        for item in items {
            let itemId = item.id?.uuidString ?? "unknown"
            let content = item.content?.prefix(30) ?? "no content"
            print("   - Deleting: \(itemId) - \(content)")
            
            item.markedAsDeleted = true
            item.lastModified = Date()
            
            // Sync to CloudKit
            Task {
                do {
                    try await cloudKitManager.pushItem(item)
                    print("     ✅ [MacBook Relay] Deletion synced: \(itemId)")
                } catch {
                    print("     ❌ [MacBook Relay] Failed to sync deletion: \(error)")
                }
            }
        }
        
        // Then delete locally
        for item in items {
            viewContext.delete(item)
        }
        saveContext()
        
        print("✅ [macOS] Batch deletion completed for \(items.count) items")
    }
    

    
    func markAsSensitive(_ item: ClipboardItem) {
        // isSensitive removed in new schema - functionality deprecated
        saveContext()
    }
    
    func updateClipboardItem(_ item: ClipboardItem, content: String) {
        item.content = content
        // contentPreview removed in new schema
        // fileSize removed in new schema
        saveContext()
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
} 