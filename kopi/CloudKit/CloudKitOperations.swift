//
//  CloudKitOperations.swift
//  kopi
//
//  Created by Wan Menzy on 20/06/2025.
//

import Foundation
import CloudKit
import CoreData

@MainActor
class CloudKitOperations {
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let persistenceController = PersistenceController.shared
    
    init() {
        container = CKContainer(identifier: "iCloud.com.wanmenzy.kopi-shared")
        privateDatabase = container.privateCloudDatabase
    }
    
    // MARK: - Core CRUD Operations
    
    /// Push a clipboard item to iCloud
    func pushItemDirectly(_ item: ClipboardItem) async throws {
        guard let itemId = item.id else {
            throw CloudKitError.invalidData("Item missing ID")
        }
        
        // Check if this is a deletion
        if item.markedAsDeleted {
            print("🗑️ [CloudKit] Deleting item from iCloud: \(itemId)")
            try await deleteItemFromCloudKit(itemId)
            return
        }
        
        // Regular save operation for non-deleted items
        let record = CKRecord(recordType: "ClipboardItem", recordID: CKRecord.ID(recordName: itemId.uuidString))
        
        // Map Core Data properties to CloudKit record
        record["content"] = item.content
        record["contentType"] = item.contentType
        record["contentHash"] = item.contentHash
        record["createdAt"] = item.createdAt
        record["createdOnDevice"] = item.createdOnDevice
        record["relayedBy"] = item.relayedBy
        record["sourceAppBundleID"] = item.sourceAppBundleID
        record["sourceAppName"] = item.sourceAppName
        record["sourceAppIcon"] = item.sourceAppIcon
        record["markedAsDeleted"] = 0 // Always 0 for non-deleted items
        record["lastModified"] = item.lastModified
        
        do {
            item.iCloudSyncStatus = SyncStatus.syncing.rawValue
            _ = try await privateDatabase.save(record)
            item.iCloudSyncStatus = SyncStatus.synced.rawValue
            item.lastModified = Date()
            
            try persistenceController.container.viewContext.save()
            
            print("✅ [CloudKit] Successfully pushed item: \(itemId)")
        } catch {
            item.iCloudSyncStatus = SyncStatus.failed.rawValue
            try persistenceController.container.viewContext.save()
            
            print("❌ [CloudKit] Failed to push item: \(error)")
            throw CloudKitError.saveFailure(error)
        }
    }
    
    /// Pull all items from iCloud
    func pullAllItems() async throws -> [ClipboardItem] {
        let query = CKQuery(recordType: "ClipboardItem", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        do {
            let (matchResults, _) = try await privateDatabase.records(matching: query)
            var cloudItems: [ClipboardItem] = []
            
            for (recordID, result) in matchResults {
                switch result {
                case .success(let record):
                    if let item = createClipboardItem(from: record) {
                        cloudItems.append(item)
                    }
                case .failure(let error):
                    print("❌ [CloudKit] Failed to fetch record \(recordID): \(error)")
                }
            }
            
            print("✅ [CloudKit] Successfully pulled \(cloudItems.count) items")
            return cloudItems
        } catch {
            print("❌ [CloudKit] Failed to pull items: \(error)")
            throw CloudKitError.fetchFailure(error)
        }
    }
    
    /// Delete an item from iCloud
    func deleteItem(id: UUID) async throws {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        
        do {
            try await privateDatabase.deleteRecord(withID: recordID)
            print("✅ [CloudKit] Successfully deleted item: \(id)")
        } catch {
            print("❌ [CloudKit] Failed to delete item: \(error)")
            throw CloudKitError.deleteFailure(error)
        }
    }
    
    private func deleteItemFromCloudKit(_ itemId: UUID) async throws {
        let recordID = CKRecord.ID(recordName: itemId.uuidString)
        
        do {
            try await privateDatabase.deleteRecord(withID: recordID)
            print("✅ [CloudKit] Successfully deleted item from iCloud: \(itemId)")
        } catch {
            // Handle the case where the record doesn't exist on the server
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                print("ℹ️ [CloudKit] Item already deleted from iCloud: \(itemId)")
                return // This is not an error - item is already gone
            }
            
            print("❌ [CloudKit] Failed to delete item from iCloud: \(error)")
            throw CloudKitError.deleteFailure(error)
        }
    }
    
    /// Subscribe to CloudKit changes for real-time updates
    func subscribeToChanges() async throws {
        let subscription = CKQuerySubscription(
            recordType: "ClipboardItem",
            predicate: NSPredicate(value: true),
            subscriptionID: "clipboard-items-subscription",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        do {
            try await privateDatabase.save(subscription)
            print("✅ [CloudKit] Successfully subscribed to changes")
        } catch {
            // Subscription might already exist
            if let ckError = error as? CKError, ckError.code == .serverRejectedRequest {
                print("ℹ️ [CloudKit] Subscription already exists")
            } else {
                print("❌ [CloudKit] Failed to subscribe: \(error)")
                throw CloudKitError.subscriptionFailure(error)
            }
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
    
    private func createClipboardItem(from record: CKRecord) -> ClipboardItem? {
        let context = persistenceController.container.viewContext
        
        guard let recordName = UUID(uuidString: record.recordID.recordName) else { return nil }
        
        // Check if item already exists locally first
        if let existingItem = findLocalItem(with: recordName) {
            // Update existing item instead of creating new one
            updateLocalItem(existingItem, from: record)
            return existingItem
        }
        
        // Create new item only if it doesn't exist
        let item = ClipboardItem(context: context)
        
        item.id = recordName
        item.content = record["content"] as? String
        item.contentType = record["contentType"] as? String
        item.contentHash = record["contentHash"] as? String
        item.createdAt = record["createdAt"] as? Date
        item.createdOnDevice = record["createdOnDevice"] as? String
        item.relayedBy = record["relayedBy"] as? String
        item.sourceAppBundleID = record["sourceAppBundleID"] as? String
        item.sourceAppName = record["sourceAppName"] as? String
        item.sourceAppIcon = record["sourceAppIcon"] as? Data
        item.markedAsDeleted = (record["markedAsDeleted"] as? Int) == 1
        item.lastModified = record["lastModified"] as? Date
        item.iCloudSyncStatus = SyncStatus.synced.rawValue
        
        return item
    }
    
    private func updateLocalItem(_ localItem: ClipboardItem, from record: CKRecord) {
        localItem.content = record["content"] as? String
        localItem.contentType = record["contentType"] as? String
        localItem.contentHash = record["contentHash"] as? String
        localItem.createdAt = record["createdAt"] as? Date
        localItem.createdOnDevice = record["createdOnDevice"] as? String
        localItem.relayedBy = record["relayedBy"] as? String
        localItem.sourceAppBundleID = record["sourceAppBundleID"] as? String
        localItem.sourceAppName = record["sourceAppName"] as? String
        localItem.sourceAppIcon = record["sourceAppIcon"] as? Data
        localItem.markedAsDeleted = (record["markedAsDeleted"] as? Int) == 1
        localItem.lastModified = record["lastModified"] as? Date
        localItem.iCloudSyncStatus = SyncStatus.synced.rawValue
    }
}
