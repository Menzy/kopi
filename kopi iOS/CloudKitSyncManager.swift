//
//  CloudKitSyncManager.swift
//  kopi iOS
//
//  Created by AI Assistant on 19/06/2025.
//

import Foundation
import CloudKit
import CoreData
import Combine

enum SyncOperation {
    case create(ClipboardItem)
    case update(ClipboardItem)
    case delete(UUID) // Using canonical ID
    case resolve(ClipboardItem)
}

enum SyncResult {
    case success(operation: SyncOperation)
    case failure(operation: SyncOperation, error: Error)
    case conflict(local: ClipboardItem, remote: ClipboardItem)
}

class CloudKitSyncManager: ObservableObject {
    static let shared = CloudKitSyncManager()
    
    private let persistenceController = PersistenceController.shared
    private let deviceManager = DeviceManager.shared
    private let idResolver = IDResolver.shared
    
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let operationQueue = OperationQueue()
    
    // Sync state tracking
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncErrors: [Error] = []
    @Published var pendingOperations: [SyncOperation] = []
    
    // Remote change tracking
    private var changeToken: CKServerChangeToken?
    private let changeTokenKey = "CloudKitChangeToken"
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        self.container = CKContainer(identifier: "iCloud.com.wanmenzy.kopi-shared")
        self.privateDatabase = container.privateCloudDatabase
        
        setupOperationQueue()
        loadChangeToken()
        setupRemoteNotifications()
        
        // Observe Core Data changes for automatic sync
        setupCoreDataObserver()
    }
    
    // MARK: - Public API
    
    /// Force sync all local changes to CloudKit
    func forceSyncAll() async {
        await MainActor.run { isSyncing = true }
        
        // Sync all pending local changes
        let pendingChanges = fetchPendingLocalChanges()
        
        for operation in pendingChanges {
            await processLocalChange(operation)
        }
        
        // Fetch remote changes
        await fetchRemoteChanges()
        
        await MainActor.run {
            lastSyncDate = Date()
            // Full sync completed (silent)
        }
        
        await MainActor.run { isSyncing = false }
    }
    
    /// Sync specific item immediately
    func syncItem(_ item: ClipboardItem, operation: SyncOperation) async {
        print("🔄 [iOS CloudKitSync] Syncing item: \(item.canonicalID?.uuidString ?? "unknown")")
        
        await MainActor.run {
            pendingOperations.append(operation)
        }
        
        await processLocalChange(operation)
        
        await MainActor.run {
            pendingOperations.removeAll { op in
                switch (op, operation) {
                case (.create(let item1), .create(let item2)),
                     (.update(let item1), .update(let item2)):
                    return item1.canonicalID == item2.canonicalID
                case (.delete(let id1), .delete(let id2)):
                    return id1 == id2
                default:
                    return false
                }
            }
        }
    }
    
    /// Delete item across all devices using canonical ID
    func deleteItemAcrossDevices(canonicalID: UUID) async {
        print("🗑️ [iOS CloudKitSync] Deleting item across devices: \(canonicalID.uuidString)")
        
        let operation = SyncOperation.delete(canonicalID)
        await processLocalChange(operation)
        
        // Also delete locally
        await deleteLocalItemsWithCanonicalID(canonicalID)
    }
    
    /// Check CloudKit availability
    func checkCloudKitAvailability() async -> Bool {
        do {
            let accountStatus = try await container.accountStatus()
            return accountStatus == .available
        } catch {
            print("❌ [iOS CloudKitSync] CloudKit not available: \(error)")
            return false
        }
    }
    
    // MARK: - Private Methods
    
    private func setupOperationQueue() {
        operationQueue.maxConcurrentOperationCount = 3
        operationQueue.qualityOfService = .userInitiated
    }
    
    private func setupRemoteNotifications() {
        // Listen for CloudKit remote change notifications
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistenceController.container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.fetchRemoteChanges()
            }
        }
    }
    
    private func setupCoreDataObserver() {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .compactMap { $0.object as? NSManagedObjectContext }
            .filter { $0 == self.persistenceController.container.viewContext }
            .sink { [weak self] context in
                Task {
                    await self?.handleCoreDataChanges(context)
                }
            }
            .store(in: &cancellables)
    }
    
    private func fetchPendingLocalChanges() -> [SyncOperation] {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        
        // Fetch items that need sync (modified recently or temporary)
        let recentDate = Date().addingTimeInterval(-3600) // Last hour
        fetchRequest.predicate = NSPredicate(
            format: "timestamp >= %@ OR isTemporary == YES",
            recentDate as NSDate
        )
        
        do {
            let items = try context.fetch(fetchRequest)
            return items.compactMap { item in
                if item.isTemporary {
                    return .resolve(item)
                } else {
                    return .update(item)
                }
            }
        } catch {
            print("❌ [iOS CloudKitSync] Error fetching local changes: \(error)")
            return []
        }
    }
    
    private func processLocalChange(_ operation: SyncOperation) async {
        switch operation {
        case .create(let item), .update(let item):
            await syncItemToCloudKit(item)
            
        case .delete(let canonicalID):
            await deleteItemFromCloudKit(canonicalID: canonicalID)
            
        case .resolve(let item):
            // Trigger ID resolution
            let result = await idResolver.resolveCanonicalID(for: item)
            switch result {
            case .resolved(let canonicalID, _):
                print("✅ [iOS CloudKitSync] Resolved item, now syncing: \(canonicalID.uuidString)")
                await syncItemToCloudKit(item)
                
            case .conflicted, .pending, .failed:
                print("⚠️ [iOS CloudKitSync] Resolution failed for item: \(item.id?.uuidString ?? "unknown")")
            }
        }
    }
    
    private func syncItemToCloudKit(_ item: ClipboardItem) async {
        guard let canonicalID = item.canonicalID else {
            print("❌ [iOS CloudKitSync] Cannot sync item without canonical ID")
            return
        }
        
        let recordID = CKRecord.ID(recordName: canonicalID.uuidString)
        let record = CKRecord(recordType: "ClipboardItem", recordID: recordID)
        
        // Set record fields
        record["content"] = item.content
        record["contentType"] = item.contentType
        record["timestamp"] = item.timestamp
        record["canonicalID"] = canonicalID.uuidString
        record["initiatingDevice"] = item.initiatingDevice
        record["syncSource"] = item.syncSource
        record["deviceOrigin"] = item.deviceOrigin
        record["isTemporary"] = item.isTemporary
        
        do {
            let savedRecord = try await privateDatabase.save(record)
            print("✅ [iOS CloudKitSync] Saved record: \(savedRecord.recordID.recordName)")
        } catch {
            print("❌ [iOS CloudKitSync] Failed to save record: \(error)")
            await MainActor.run {
                syncErrors.append(error)
            }
        }
    }
    
    private func deleteItemFromCloudKit(canonicalID: UUID) async {
        let recordID = CKRecord.ID(recordName: canonicalID.uuidString)
        
        do {
            try await privateDatabase.deleteRecord(withID: recordID)
            print("✅ [iOS CloudKitSync] Deleted record: \(canonicalID.uuidString)")
        } catch {
            print("❌ [iOS CloudKitSync] Failed to delete record: \(error)")
            await MainActor.run {
                syncErrors.append(error)
            }
        }
    }
    
    private func fetchRemoteChanges() async {
        // Fetching remote changes silently
        
        let changesOperation = CKFetchDatabaseChangesOperation(previousServerChangeToken: changeToken)
        
        changesOperation.recordZoneWithIDChangedBlock = { zoneID in
            Task {
                await self.fetchZoneChanges(zoneID: zoneID)
            }
        }
        
        changesOperation.changeTokenUpdatedBlock = { token in
            self.changeToken = token
            self.saveChangeToken()
        }
        
        changesOperation.fetchDatabaseChangesResultBlock = { result in
            switch result {
            case .success(let serverChangeTokenAndMoreComing):
                self.changeToken = serverChangeTokenAndMoreComing.serverChangeToken
                self.saveChangeToken()
                // Remote changes fetched successfully (silent)
                
            case .failure(let error):
                print("❌ [iOS CloudKitSync] Failed to fetch remote changes: \(error)")
                Task {
                    await MainActor.run {
                        self.syncErrors.append(error)
                    }
                }
            }
        }
        
        privateDatabase.add(changesOperation)
    }
    
    private func fetchZoneChanges(zoneID: CKRecordZone.ID) async {
        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], configurationsByRecordZoneID: [:])
        
        operation.recordWasChangedBlock = { recordID, result in
            switch result {
            case .success(let record):
                Task {
                    await self.handleRemoteRecordChange(record)
                }
            case .failure(let error):
                print("❌ [iOS CloudKitSync] Record change error: \(error)")
            }
        }
        
        operation.recordWithIDWasDeletedBlock = { recordID, recordType in
            Task {
                await self.handleRemoteRecordDeletion(recordID: recordID)
            }
        }
        
        privateDatabase.add(operation)
    }
    
    private func handleRemoteRecordChange(_ record: CKRecord) async {
        guard record.recordType == "ClipboardItem",
              let canonicalIDString = record["canonicalID"] as? String,
              let canonicalID = UUID(uuidString: canonicalIDString) else {
            return
        }
        
        // Processing remote record change silently
        
        // Check if we already have this item locally
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "canonicalID == %@", canonicalID as CVarArg)
        fetchRequest.fetchLimit = 1
        
        do {
            let existingItems = try context.fetch(fetchRequest)
            
            if let existingItem = existingItems.first {
                // Update existing item
                await updateLocalItem(existingItem, with: record)
            } else {
                // Create new item from remote record
                await createLocalItem(from: record)
            }
        } catch {
            print("❌ [iOS CloudKitSync] Error processing remote change: \(error)")
        }
    }
    
    private func handleRemoteRecordDeletion(recordID: CKRecord.ID) async {
        guard let canonicalID = UUID(uuidString: recordID.recordName) else { return }
        
        // Processing remote deletion silently
        await deleteLocalItemsWithCanonicalID(canonicalID)
    }
    
    private func updateLocalItem(_ item: ClipboardItem, with record: CKRecord) async {
        let context = persistenceController.container.viewContext
        
        await context.perform {
            // Mark this as a CloudKit-initiated change to prevent sync loops
            context.userInfo["fromCloudKit"] = true
            defer {
                context.userInfo.removeObject(forKey: "fromCloudKit")
            }
            
            // Update fields from CloudKit record
            item.content = record["content"] as? String
            item.contentType = record["contentType"] as? String
            item.timestamp = record["timestamp"] as? Date
            item.initiatingDevice = record["initiatingDevice"] as? String
            item.syncSource = record["syncSource"] as? String
            item.isTemporary = (record["isTemporary"] as? Bool) ?? false
            
            do {
                try context.save()
                // Updated local item from remote (silent)
            } catch {
                print("❌ [iOS CloudKitSync] Failed to update local item: \(error)")
            }
        }
    }
    
    private func createLocalItem(from record: CKRecord) async {
        let context = persistenceController.container.viewContext
        
        await context.perform {
            // Mark this as a CloudKit-initiated change to prevent sync loops
            context.userInfo["fromCloudKit"] = true
            defer {
                context.userInfo.removeObject(forKey: "fromCloudKit")
            }
            
            let item = ClipboardItem(context: context)
            
            // Set fields from CloudKit record
            item.id = UUID()
            item.content = record["content"] as? String
            item.contentType = record["contentType"] as? String
            item.timestamp = record["timestamp"] as? Date ?? Date()
            item.deviceOrigin = record["deviceOrigin"] as? String
            item.initiatingDevice = record["initiatingDevice"] as? String
            item.syncSource = record["syncSource"] as? String
            item.isTemporary = (record["isTemporary"] as? Bool) ?? false
            
            if let canonicalIDString = record["canonicalID"] as? String {
                item.canonicalID = UUID(uuidString: canonicalIDString)
            }
            
            // Set additional computed fields
            item.contentPreview = item.content?.prefix(100).description
            item.fileSize = Int64(item.content?.data(using: .utf8)?.count ?? 0)
            item.isTransient = false
            item.isSensitive = false
            
            do {
                try context.save()
                // Created local item from remote (silent)
            } catch {
                print("❌ [iOS CloudKitSync] Failed to create local item: \(error)")
            }
        }
    }
    
    private func deleteLocalItemsWithCanonicalID(_ canonicalID: UUID) async {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "canonicalID == %@", canonicalID as CVarArg)
        
        await context.perform {
            // Mark this as a CloudKit-initiated change to prevent sync loops
            context.userInfo["fromCloudKit"] = true
            defer {
                context.userInfo.removeObject(forKey: "fromCloudKit")
            }
            
            do {
                let items = try context.fetch(fetchRequest)
                for item in items {
                    context.delete(item)
                    // Deleted local item (silent)
                }
                try context.save()
            } catch {
                print("❌ [iOS CloudKitSync] Failed to delete local items: \(error)")
            }
        }
    }
    
    private func handleCoreDataChanges(_ context: NSManagedObjectContext) async {
        // Prevent sync loops - only sync user-initiated changes, not CloudKit-initiated ones
        guard !isSyncing else { return }
        
        // Check if this is a CloudKit-initiated change (to prevent loops)
        if context.userInfo["fromCloudKit"] as? Bool == true {
            return // Don't sync changes that came from CloudKit
        }
        
        // Small delay to batch rapid changes
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        await forceSyncAll()
    }
    
    private func loadChangeToken() {
        if let data = UserDefaults.standard.data(forKey: changeTokenKey),
           let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data) {
            changeToken = token
        }
    }
    
    private func saveChangeToken() {
        guard let token = changeToken else { return }
        
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            UserDefaults.standard.set(data, forKey: changeTokenKey)
        } catch {
            print("❌ [iOS CloudKitSync] Failed to save change token: \(error)")
        }
    }
}