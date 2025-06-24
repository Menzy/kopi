//
//  CloudKitManager.swift
//  kopi iOS
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
    
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    
    // MARK: - iOS Sync Client Properties (Simplified)
    private var lastFullSyncDate: Date?
    
    private init() {
        container = CKContainer(identifier: "iCloud.com.wanmenzy.kopi-shared")
        privateDatabase = container.privateCloudDatabase
        
        setupNetworkMonitoring()
    }
    
    // MARK: - Enhanced Core CloudKit Operations
    
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
        
        do {
            try context.save()
            
            // Refresh the context to ensure UI updates
            await MainActor.run {
                context.refreshAllObjects()
            }
            
            print("✅ [iOS Smart Merge] Reconciliation complete - Reconciled: \(reconciledCount), New: \(newItemsCount), Conflicts: \(conflictCount)")
        } catch {
            print("❌ [iOS Smart Merge] Failed to save reconciled items: \(error)")
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
        // Phase 5: Intelligent conflict resolution
        
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
    
    // MARK: - Helper Methods
    
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
                    print("🌐 [iOS CloudKit] Network connected")
                    
                    if !wasConnected {
                        // Coming back online - perform sync
                        await self?.syncFromCloud()
                    }
                } else {
                    print("📵 [iOS CloudKit] Network disconnected")
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }
    
    // MARK: - iOS Sync Client Operations (Simplified)
    
    private func performFullReconciliationSync() async {
        do {
            syncStatus = .syncing
            
            // Pull all items from cloud for full reconciliation
            let cloudItems = try await pullAllItems()
            
            // Perform enhanced reconciliation
            await reconcileItems(cloudItems)
            
            // Update last full sync date
            lastFullSyncDate = Date()
            UserDefaults.standard.set(lastFullSyncDate, forKey: "LastFullSyncDate_iOS")
            
            syncStatus = .synced
            print("✅ [iOS Full Sync] Full reconciliation sync completed")
            
        } catch {
            syncStatus = .failed
            print("❌ [iOS Full Sync] Full reconciliation sync failed: \(error)")
        }
    }
    
    // MARK: - Public Sync Operations (Simplified for iOS)
    
    /// iOS-specific sync - only pulls from iCloud, never pushes
    func syncFromCloud() async {
        // iOS is purely a sync client - only pulls from iCloud
        do {
            syncStatus = .syncing
            let cloudItems = try await pullAllItems()
            await reconcileItems(cloudItems)
            syncStatus = .synced
            print("✅ [iOS CloudKit] Successfully synced from iCloud")
        } catch {
            syncStatus = .failed
            print("❌ [iOS CloudKit] Sync failed: \(error)")
        }
    }
    
    /// Force a full reconciliation sync (iOS only pulls)
    func forceFullSync() async {
        await performFullReconciliationSync()
    }
    
    /// Get offline queue status (always returns 0 for iOS since no pushing)
    func getOfflineQueueStatus() -> (count: Int, oldestOperation: Date?) {
        return (count: 0, oldestOperation: nil)
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