//
//  CloudKitManager.swift
//  kopi
//
//  Created by Wan Menzy on 20/06/2025.
//

import Foundation
import CloudKit
import CoreData
import Network

@MainActor
class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()
    
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let persistenceController = PersistenceController.shared
    
    @Published var syncStatus: SyncStatus = .local
    @Published var isConnected: Bool = false
    @Published var offlineQueueCount: Int = 0
    
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    
    // MARK: - Phase 5: Offline Queue Management
    private var offlineOperationQueue: [OfflineOperation] = []
    private let offlineQueueLock = NSLock()
    private var lastFullSyncDate: Date?
    private var connectionStateChangeHandler: (() -> Void)?
    
    private init() {
        container = CKContainer(identifier: "iCloud.com.wanmenzy.kopi-shared")
        privateDatabase = container.privateCloudDatabase
        
        setupNetworkMonitoring()
        loadOfflineQueue()
    }
    
    // MARK: - Phase 5: Enhanced Offline Queue System
    
    private enum OfflineOperation: Codable {
        case pushItem(itemId: UUID, contentHash: String, timestamp: Date)
        case deleteItem(itemId: UUID, timestamp: Date)
        case updateItem(itemId: UUID, contentHash: String, timestamp: Date)
        
        var timestamp: Date {
            switch self {
            case .pushItem(_, _, let timestamp),
                 .deleteItem(_, let timestamp),
                 .updateItem(_, _, let timestamp):
                return timestamp
            }
        }
        
        var itemId: UUID {
            switch self {
            case .pushItem(let itemId, _, _),
                 .deleteItem(let itemId, _),
                 .updateItem(let itemId, _, _):
                return itemId
            }
        }
    }
    
    private func queueOfflineOperation(_ operation: OfflineOperation) {
        offlineQueueLock.lock()
        defer { offlineQueueLock.unlock() }
        
        // Remove any existing operations for the same item to avoid duplicates
        offlineOperationQueue.removeAll { $0.itemId == operation.itemId }
        
        // Add new operation
        offlineOperationQueue.append(operation)
        offlineQueueCount = offlineOperationQueue.count
        
        saveOfflineQueue()
        
        print("📤 [Offline Queue] Added operation for item: \(operation.itemId)")
        print("📊 [Offline Queue] Queue size: \(offlineOperationQueue.count)")
    }
    
    private func processOfflineQueue() async {
        guard isConnected else { return }
        
        let operations = await getOperationsToProcess()
        guard !operations.isEmpty else { return }
        
        print("🔄 [Offline Queue] Processing \(operations.count) queued operations")
        
        var processedOperations: [OfflineOperation] = []
        
        for operation in operations.sorted(by: { $0.timestamp < $1.timestamp }) {
            do {
                switch operation {
                case .pushItem(let itemId, _, _):
                    if let item = findLocalItem(with: itemId) {
                        try await pushItemDirectly(item)
                    }
                case .deleteItem(let itemId, _):
                    try await deleteItem(id: itemId)
                case .updateItem(let itemId, _, _):
                    if let item = findLocalItem(with: itemId) {
                        try await pushItemDirectly(item)
                    }
                }
                
                processedOperations.append(operation)
                print("✅ [Offline Queue] Successfully processed: \(operation.itemId)")
                
            } catch {
                print("❌ [Offline Queue] Failed to process operation: \(error)")
                // Keep failed operations in queue for retry
                break
            }
        }
        
        // Remove successfully processed operations
        await removeProcessedOperations(processedOperations)
        
        print("🔄 [Offline Queue] Processed \(processedOperations.count) operations, \(offlineQueueCount) remaining")
    }
    
    private func getOperationsToProcess() async -> [OfflineOperation] {
        return await MainActor.run {
            self.offlineQueueLock.lock()
            defer { self.offlineQueueLock.unlock() }
            return self.offlineOperationQueue
        }
    }
    
    private func removeProcessedOperations(_ processedOperations: [OfflineOperation]) async {
        await MainActor.run {
            self.offlineQueueLock.lock()
            defer { self.offlineQueueLock.unlock() }
            
            for processedOp in processedOperations {
                self.offlineOperationQueue.removeAll { $0.itemId == processedOp.itemId && $0.timestamp == processedOp.timestamp }
            }
            
            self.offlineQueueCount = self.offlineOperationQueue.count
            self.saveOfflineQueue()
        }
    }
    
    private func saveOfflineQueue() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(offlineOperationQueue) {
            UserDefaults.standard.set(data, forKey: "OfflineOperationQueue")
        }
    }
    
    private func loadOfflineQueue() {
        if let data = UserDefaults.standard.data(forKey: "OfflineOperationQueue"),
           let queue = try? JSONDecoder().decode([OfflineOperation].self, from: data) {
            offlineOperationQueue = queue
            offlineQueueCount = queue.count
            print("📂 [Offline Queue] Loaded \(queue.count) queued operations")
        }
    }
    
    // MARK: - Enhanced Core CloudKit Operations
    
    /// Push a clipboard item to iCloud with offline queue support
    func pushItem(_ item: ClipboardItem) async throws {
        guard let itemId = item.id else {
            throw CloudKitError.invalidData("Item missing ID")
        }
        
        // Phase 5: If offline, queue the operation
        if !isConnected {
            let operation = OfflineOperation.pushItem(
                itemId: itemId,
                contentHash: item.contentHash ?? "",
                timestamp: Date()
            )
            queueOfflineOperation(operation)
            
            item.iCloudSyncStatus = SyncStatus.local.rawValue
            try persistenceController.container.viewContext.save()
            
            print("📤 [Offline Queue] Queued push for item: \(itemId)")
            return
        }
        
        try await pushItemDirectly(item)
    }
    
    private func pushItemDirectly(_ item: ClipboardItem) async throws {
        guard let itemId = item.id else {
            throw CloudKitError.invalidData("Item missing ID")
        }
        
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
        record["markedAsDeleted"] = item.markedAsDeleted ? 1 : 0
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
        guard isConnected else {
            throw CloudKitError.notConnected
        }
        
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
    
    /// Delete an item from iCloud with offline queue support
    func deleteItem(id: UUID) async throws {
        // Phase 5: If offline, queue the operation
        if !isConnected {
            let operation = OfflineOperation.deleteItem(itemId: id, timestamp: Date())
            queueOfflineOperation(operation)
            
            // Mark as deleted locally
            if let localItem = findLocalItem(with: id) {
                localItem.markedAsDeleted = true
                localItem.lastModified = Date()
                try persistenceController.container.viewContext.save()
            }
            
            print("📤 [Offline Queue] Queued deletion for item: \(id)")
            return
        }
        
        let recordID = CKRecord.ID(recordName: id.uuidString)
        
        do {
            try await privateDatabase.deleteRecord(withID: recordID)
            print("✅ [CloudKit] Successfully deleted item: \(id)")
        } catch {
            print("❌ [CloudKit] Failed to delete item: \(error)")
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
    
    /// Handle remote notification from CloudKit
    func handleRemoteNotification(_ notification: CKNotification) async {
        guard let queryNotification = notification as? CKQueryNotification else { return }
        
        print("📡 [CloudKit] Received remote notification: \(queryNotification.queryNotificationReason)")
        
        // Trigger a sync when we receive changes
        await syncFromCloud()
    }
    
    // MARK: - Phase 5: Enhanced Reconciliation with Smart Merge Strategies
    
    private func reconcileItems(_ cloudItems: [ClipboardItem]) async {
        let context = persistenceController.container.viewContext
        var reconciledCount = 0
        var conflictCount = 0
        var newItemsCount = 0
        
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
        
        do {
            try context.save()
            print("✅ [Smart Merge] Reconciliation complete - Reconciled: \(reconciledCount), New: \(newItemsCount), Conflicts: \(conflictCount)")
        } catch {
            print("❌ [Smart Merge] Failed to save reconciled items: \(error)")
        }
    }
    
    private enum ReconciliationResult {
        case localWins
        case cloudWins
        case conflict
        case merged
    }
    
    private func performSmartReconciliation(localItem: ClipboardItem, cloudItem: ClipboardItem) async -> ReconciliationResult {
        // Phase 5: Smart merge strategies based on multiple factors
        
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
        // Phase 5: Conflict resolution strategies
        
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
    
    // MARK: - Helper Methods
    
    private func createClipboardItem(from record: CKRecord) -> ClipboardItem? {
        let context = persistenceController.container.viewContext
        let item = ClipboardItem(context: context)
        
        guard let recordName = UUID(uuidString: record.recordID.recordName) else { return nil }
        
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
    
    private func findLocalItem(with id: UUID?) -> ClipboardItem? {
        guard let id = id else { return nil }
        
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        
        return try? context.fetch(request).first
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
    
    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasConnected = self?.isConnected ?? false
                self?.isConnected = path.status == .satisfied
                
                if path.status == .satisfied {
                    print("🌐 [CloudKit] Network connected")
                    
                    if !wasConnected {
                        // Coming back online - process offline queue and perform full sync
                        await self?.handleReconnection()
                    } else {
                        // Regular sync
                        await self?.syncFromCloud()
                    }
                } else {
                    print("📵 [CloudKit] Network disconnected - operations will be queued")
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }
    
    // MARK: - Phase 5: Reconnection Handling
    
    private func handleReconnection() async {
        print("🔄 [Reconnection] Handling reconnection to iCloud")
        
        // 1. Process offline queue first
        await processOfflineQueue()
        
        // 2. Perform full reconciliation sync
        await performFullReconciliationSync()
        
        print("✅ [Reconnection] Reconnection handling complete")
    }
    
    private func performFullReconciliationSync() async {
        do {
            syncStatus = .syncing
            
            // Pull all items from cloud for full reconciliation
            let cloudItems = try await pullAllItems()
            
            // Perform enhanced reconciliation
            await reconcileItems(cloudItems)
            
            // Update last full sync date
            lastFullSyncDate = Date()
            UserDefaults.standard.set(lastFullSyncDate, forKey: "LastFullSyncDate")
            
            syncStatus = .synced
            print("✅ [Full Sync] Full reconciliation sync completed")
            
        } catch {
            syncStatus = .failed
            print("❌ [Full Sync] Full reconciliation sync failed: \(error)")
        }
    }
    
    // MARK: - Public Sync Operations (Enhanced)
    
    /// Enhanced sync with offline queue processing
    func syncFromCloud() async {
        // Process offline queue first if connected
        if isConnected {
            await processOfflineQueue()
        }
        
        // Then perform regular sync
        do {
            syncStatus = .syncing
            let cloudItems = try await pullAllItems()
            await reconcileItems(cloudItems)
            syncStatus = .synced
        } catch {
            syncStatus = .failed
            print("❌ [CloudKit] Sync failed: \(error)")
        }
    }
    
    /// Force a full reconciliation sync
    func forceFullSync() async {
        await performFullReconciliationSync()
    }
    
    /// Get offline queue status
    func getOfflineQueueStatus() -> (count: Int, oldestOperation: Date?) {
        offlineQueueLock.lock()
        defer { offlineQueueLock.unlock() }
        
        let count = offlineOperationQueue.count
        let oldestDate = offlineOperationQueue.min(by: { $0.timestamp < $1.timestamp })?.timestamp
        
        return (count: count, oldestOperation: oldestDate)
    }
}

// MARK: - CloudKit Errors

enum CloudKitError: LocalizedError {
    case notConnected
    case invalidData(String)
    case saveFailure(Error)
    case fetchFailure(Error)
    case deleteFailure(Error)
    case subscriptionFailure(Error)
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No internet connection available"
        case .invalidData(let message):
            return "Invalid data: \(message)"
        case .saveFailure(let error):
            return "Failed to save to CloudKit: \(error.localizedDescription)"
        case .fetchFailure(let error):
            return "Failed to fetch from CloudKit: \(error.localizedDescription)"
        case .deleteFailure(let error):
            return "Failed to delete from CloudKit: \(error.localizedDescription)"
        case .subscriptionFailure(let error):
            return "Failed to subscribe to CloudKit: \(error.localizedDescription)"
        }
    }
} 