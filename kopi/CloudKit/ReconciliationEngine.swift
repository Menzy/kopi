//
//  ReconciliationEngine.swift
//  kopi
//
//  Created by Wan Menzy on 20/06/2025.
//

import Foundation
import CoreData

@MainActor
class ReconciliationEngine {
    private let persistenceController = PersistenceController.shared
    
    enum ReconciliationResult {
        case localWins
        case cloudWins
        case conflict
        case merged
    }
    
    // MARK: - Main Reconciliation
    
    func reconcileItems(_ cloudItems: [ClipboardItem]) async {
        let context = persistenceController.container.viewContext
        var reconciledCount = 0
        var conflictCount = 0
        var newItemsCount = 0
        var deletedCount = 0
        
        // Get all local items for deletion reconciliation
        let localItems = getAllLocalItems()
        let cloudItemIDs = Set(cloudItems.compactMap { $0.id })
        
        // Process cloud items (updates and new items)
        for cloudItem in cloudItems {
            // Check if we already have this item locally
            if let existingItem = findLocalItem(with: cloudItem.id) {
                let reconciliationResult = await performSmartReconciliation(
                    localItem: existingItem,
                    cloudItem: cloudItem
                )
                
                switch reconciliationResult {
                case .localWins:
                    print("🏆 [Smart Merge] Local version wins: \(existingItem.id?.uuidString ?? "unknown")")
                case .cloudWins:
                    print("☁️ [Smart Merge] Cloud version wins: \(cloudItem.id?.uuidString ?? "unknown")")
                    updateLocalItem(existingItem, from: cloudItem)
                case .conflict:
                    print("⚠️ [Smart Merge] Conflict detected: \(cloudItem.id?.uuidString ?? "unknown")")
                    await handleConflict(localItem: existingItem, cloudItem: cloudItem)
                    conflictCount += 1
                case .merged:
                    print("🔀 [Smart Merge] Items merged: \(cloudItem.id?.uuidString ?? "unknown")")
                }
                
                reconciledCount += 1
            } else {
                // New item from cloud - check for hash-based deduplication
                if !isDuplicateContent(cloudItem) {
                    context.insert(cloudItem)
                    newItemsCount += 1
                    print("📥 [Smart Merge] New item from cloud: \(cloudItem.id?.uuidString ?? "unknown")")
                } else {
                    print("🔍 [Hash Dedup] Skipped duplicate content: \(cloudItem.contentHash ?? "no-hash")")
                }
            }
        }
        
        // Handle deletions: Remove local items that no longer exist on CloudKit
        for localItem in localItems {
            guard let localItemID = localItem.id else { continue }
            
            // If local item doesn't exist in cloud items, it was deleted on another device
            if !cloudItemIDs.contains(localItemID) {
                print("🗑️ [macOS Deletion Sync] Deleting local item that was removed from CloudKit: \(localItemID)")
                context.delete(localItem)
                deletedCount += 1
            }
        }
        
        do {
            try context.save()
            print("✅ [Smart Merge] Reconciliation complete - Reconciled: \(reconciledCount), New: \(newItemsCount), Deleted: \(deletedCount), Conflicts: \(conflictCount)")
            
            // Post notification to refresh UI if any changes were made
            if reconciledCount > 0 || newItemsCount > 0 || deletedCount > 0 {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .cloudKitSyncCompleted, object: nil)
                }
            }
        } catch {
            print("❌ [Smart Merge] Failed to save reconciled items: \(error)")
        }
    }
    
    // MARK: - Smart Reconciliation Logic
    
    private func performSmartReconciliation(localItem: ClipboardItem, cloudItem: ClipboardItem) async -> ReconciliationResult {
        // 1. Hash-based content comparison (primary)
        if let localHash = localItem.contentHash,
           let cloudHash = cloudItem.contentHash {
            
            if ContentHashingUtility.compareContentHashes(localHash, cloudHash) {
                // Same content - check timestamps for metadata updates
                if let cloudModified = cloudItem.lastModified,
                   let localModified = localItem.lastModified {
                    
                    if cloudModified > localModified {
                        localItem.iCloudSyncStatus = SyncStatus.synced.rawValue
                        localItem.lastModified = cloudModified
                        return .cloudWins
                    } else {
                        localItem.iCloudSyncStatus = SyncStatus.synced.rawValue
                        return .localWins
                    }
                }
                
                localItem.iCloudSyncStatus = SyncStatus.synced.rawValue
                return .localWins
            }
        }
        
        // 2. Timestamp-based resolution for different content
        if let cloudModified = cloudItem.lastModified,
           let localModified = localItem.lastModified {
            
            let timeDifference = abs(cloudModified.timeIntervalSince(localModified))
            
            // If changes are very close in time (< 10 seconds), it might be a conflict
            if timeDifference < 10.0 {
                return .conflict
            } else if cloudModified > localModified {
                return .cloudWins
            } else {
                return .localWins
            }
        }
        
        // 3. Device origin priority (MacBook relay > iPhone direct)
        if let cloudDevice = cloudItem.createdOnDevice,
           let localDevice = localItem.createdOnDevice {
            
            if cloudDevice.contains("MacBook") && !localDevice.contains("MacBook") {
                return .cloudWins
            } else if localDevice.contains("MacBook") && !cloudDevice.contains("MacBook") {
                return .localWins
            }
        }
        
        // 4. Default: Cloud wins (last resort)
        return .cloudWins
    }
    
    private func handleConflict(localItem: ClipboardItem, cloudItem: ClipboardItem) async {
        // Strategy 1: Content length (prefer longer content as more complete)
        let localLength = localItem.content?.count ?? 0
        let cloudLength = cloudItem.content?.count ?? 0
        
        if cloudLength > Int(Double(localLength) * 1.2) { // Cloud content is 20% longer
            print("📏 [Conflict Resolution] Cloud version has more content")
            updateLocalItem(localItem, from: cloudItem)
            return
        } else if localLength > Int(Double(cloudLength) * 1.2) { // Local content is 20% longer
            print("📏 [Conflict Resolution] Local version has more content - keeping local")
            return
        }
        
        // Strategy 2: Recency wins
        if let cloudModified = cloudItem.lastModified,
           let localModified = localItem.lastModified,
           cloudModified > localModified {
            print("⏰ [Conflict Resolution] Cloud version is more recent")
            updateLocalItem(localItem, from: cloudItem)
        } else {
            print("⏰ [Conflict Resolution] Local version is more recent - keeping local")
        }
    }
    
    // MARK: - Helper Methods
    
    func findLocalItem(with id: UUID?) -> ClipboardItem? {
        guard let id = id else { return nil }
        
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        
        return try? context.fetch(request).first
    }
    
    private func getAllLocalItems() -> [ClipboardItem] {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        
        do {
            return try context.fetch(request)
        } catch {
            print("❌ [macOS CloudKit] Error fetching local items: \(error)")
            return []
        }
    }
    
    private func isDuplicateContent(_ item: ClipboardItem) -> Bool {
        guard let hash = item.contentHash else { return false }
        
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.predicate = NSPredicate(format: "contentHash == %@ AND id != %@", 
                                       hash, item.id as CVarArg? ?? UUID() as CVarArg)
        request.fetchLimit = 1
        
        do {
            let existingItems = try context.fetch(request)
            return !existingItems.isEmpty
        } catch {
            print("❌ [Hash Dedup] Error checking for duplicates: \(error)")
            return false
        }
    }
    
    private func updateLocalItem(_ localItem: ClipboardItem, from cloudItem: ClipboardItem) {
        localItem.content = cloudItem.content
        localItem.contentType = cloudItem.contentType
        localItem.contentHash = cloudItem.contentHash
        localItem.createdAt = cloudItem.createdAt
        localItem.createdOnDevice = cloudItem.createdOnDevice
        localItem.relayedBy = cloudItem.relayedBy
        localItem.sourceAppBundleID = cloudItem.sourceAppBundleID
        localItem.sourceAppName = cloudItem.sourceAppName
        localItem.sourceAppIcon = cloudItem.sourceAppIcon
        localItem.markedAsDeleted = cloudItem.markedAsDeleted
        localItem.lastModified = cloudItem.lastModified
        localItem.iCloudSyncStatus = SyncStatus.synced.rawValue
    }
}
