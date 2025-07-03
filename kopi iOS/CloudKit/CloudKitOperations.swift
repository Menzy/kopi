//
//  CloudKitOperations.swift
//  kopi iOS
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
    
    // MARK: - Core Operations (iOS - Read Only + Delete)
    
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
    
    /// Delete an item from iCloud (iOS can delete even though it's read-only for creation)
    func deleteItem(id: UUID) async throws {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        
        do {
            try await privateDatabase.deleteRecord(withID: recordID)
            print("✅ [iOS CloudKit] Successfully deleted item from iCloud: \(id)")
        } catch {
            // Handle the case where the record doesn't exist on the server
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                print("ℹ️ [iOS CloudKit] Item already deleted from iCloud: \(id)")
                return // This is not an error - item is already gone
            }
            
            print("❌ [iOS CloudKit] Failed to delete item from iCloud: \(error)")
            throw CloudKitError.deleteFailure(error)
        }
    }
    
    /// iOS does not create subscriptions - only macOS handles CloudKit subscriptions
    /// This is a no-op function to maintain compatibility
    func subscribeToChanges() async throws {
        print("ℹ️ [iOS CloudKit] Subscription skipped - iOS is read-only, macOS handles subscriptions")
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
