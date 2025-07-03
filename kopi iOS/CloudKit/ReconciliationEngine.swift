//
//  ReconciliationEngine.swift
//  kopi iOS
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
                    print("🏆 [iOS Smart Merge] Local version wins: \(existingItem.id?.uuidString ?? "unknown")")
                case .cloudWins:
                    print("☁️ [iOS Smart Merge] Cloud version wins: \(cloudItem.id?.uuidString ?? "unknown")")
                    updateLocalItem(existingItem, from: cloudItem)
                case .conflict:
                    print("⚠️ [iOS Smart Merge] Conflict detected: \(cloudItem.id?.uuidString ?? "unknown")")
                    await handleConflict(localItem: existingItem, cloudItem: cloudItem)
                    conflictCount += 1
                case .merged:
                    print("🔀 [iOS Smart Merge] Items merged: \(cloudItem.id?.uuidString ?? "unknown")")
                }
                
                reconciledCount += 1
            } else {
                // New item from cloud - check for hash-based deduplication
                if !isDuplicateContent(cloudItem) {
                    // Don't insert cloudItem directly - it's already been created by createClipboardItem
                    // The cloudItem is already in the context, just mark it properly
                    cloudItem.iCloudSyncStatus = SyncStatus.synced.rawValue
                    newItemsCount += 1
                    print("📥 [iOS Smart Merge] New item from cloud: \(cloudItem.id?.uuidString ?? "unknown")")
                } else {
                    print("🔍 [iOS Hash Dedup] Skipped duplicate content: \(cloudItem.contentHash ?? "no-hash")")
                    // Remove the duplicate item from context
                    context.delete(cloudItem)
                }
            }
        }
        
        // Handle deletions: Remove local items that no longer exist on CloudKit
        for localItem in localItems {
            guard let localItemID = localItem.id else { continue }
            
            // If local item doesn't exist in cloud items, it was deleted on another device
            if !cloudItemIDs.contains(localItemID) {
                print("🗑️ [iOS Deletion Sync] Deleting local item that was removed from CloudKit: \(localItemID)")
                context.delete(localItem)
                deletedCount += 1
            }
        }
        
        do {
            try context.save()
            
            // Refresh the context to ensure UI updates
            await MainActor.run {
                context.refreshAllObjects()
            }
            
            print("✅ [iOS Smart Merge] Reconciliation complete - Reconciled: \(reconciledCount), New: \(newItemsCount), Deleted: \(deletedCount), Conflicts: \(conflictCount)")
        } catch {
            print("❌ [iOS Smart Merge] Failed to save reconciled items: \(error)")
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
                
                // Default to local wins if timestamps are missing
                localItem.iCloudSyncStatus = SyncStatus.synced.rawValue
                return .localWins
            }
        }
        
        // 2. Timestamp-based comparison (secondary)
        if let localModified = localItem.lastModified,
           let cloudModified = cloudItem.lastModified {
            
            let timeDifference = abs(cloudModified.timeIntervalSince(localModified))
            
            // If timestamps are very close (within 2 seconds), it might be a race condition
            if timeDifference < 2.0 {
                // Use device identifier as tie-breaker for consistency
                let localDevice = localItem.createdOnDevice ?? ""
                let cloudDevice = cloudItem.createdOnDevice ?? ""
                
                if localDevice == ContentHashingUtility.getDeviceIdentifier() {
                    return .localWins
                } else if cloudDevice != ContentHashingUtility.getDeviceIdentifier() {
                    return .cloudWins
                } else {
                    return .conflict
                }
            }
            
            // Clear timestamp winner
            return cloudModified > localModified ? .cloudWins : .localWins
        }
        
        // 3. Fallback to conflict resolution
        return .conflict
    }
    
    private func handleConflict(localItem: ClipboardItem, cloudItem: ClipboardItem) async {
        // Strategy 1: Content length preference (longer content often contains more info)
        let localContentLength = localItem.content?.count ?? 0
        let cloudContentLength = cloudItem.content?.count ?? 0
        
        if cloudContentLength > Int(Double(localContentLength) * 1.5) {
            print("🔀 [iOS Conflict] Choosing cloud item (significantly longer content)")
            updateLocalItem(localItem, from: cloudItem)
            return
        } else if localContentLength > Int(Double(cloudContentLength) * 1.5) {
            print("🔀 [iOS Conflict] Keeping local item (significantly longer content)")
            localItem.iCloudSyncStatus = SyncStatus.synced.rawValue
            return
        }
        
        // Strategy 2: Device preference (prefer items created on this device)
        if localItem.createdOnDevice == ContentHashingUtility.getDeviceIdentifier() {
            print("🔀 [iOS Conflict] Keeping local item (created on this device)")
            localItem.iCloudSyncStatus = SyncStatus.synced.rawValue
            return
        }
        
        // Strategy 3: Default to most recent
        if let localModified = localItem.lastModified,
           let cloudModified = cloudItem.lastModified {
            if cloudModified > localModified {
                print("🔀 [iOS Conflict] Choosing cloud item (more recent)")
                updateLocalItem(localItem, from: cloudItem)
            } else {
                print("🔀 [iOS Conflict] Keeping local item (more recent)")
                localItem.iCloudSyncStatus = SyncStatus.synced.rawValue
            }
        } else {
            // Final fallback - keep local
            print("🔀 [iOS Conflict] Keeping local item (fallback)")
            localItem.iCloudSyncStatus = SyncStatus.synced.rawValue
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
        request.predicate = NSPredicate(format: "markedAsDeleted == NO")
        
        do {
            return try context.fetch(request)
        } catch {
            print("❌ [iOS Deletion Sync] Failed to fetch local items: \(error)")
            return []
        }
    }
    
    private func isDuplicateContent(_ item: ClipboardItem) -> Bool {
        guard let hash = item.contentHash, let itemId = item.id else { return false }
        
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.predicate = NSPredicate(format: "contentHash == %@ AND id != %@", 
                                       hash, itemId as CVarArg)
        request.fetchLimit = 1
        
        do {
            let existingItems = try context.fetch(request)
            let hasDuplicate = !existingItems.isEmpty
            
            if hasDuplicate {
                print("🔍 [iOS Hash Dedup] Found duplicate content for item \(itemId): \(hash)")
            }
            
            return hasDuplicate
        } catch {
            print("❌ [iOS Hash Dedup] Error checking for duplicates: \(error)")
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
