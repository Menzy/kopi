//
//  CloudKitManager.swift
//  kopi
//
//  Created by Wan Menzy on 20/06/2025.
//

import Foundation
import CloudKit
import CoreData

@MainActor
class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()
    
    // Published properties
    @Published var syncStatus: SyncStatus = .local
    @Published var isConnected: Bool = false
    @Published var offlineQueueCount: Int = 0
    
    // Components
    private let operations: CloudKitOperations
    private let offlineQueue: OfflineQueue
    private let reconciler: ReconciliationEngine
    private let networkMonitor: NetworkMonitor
    private let syncCoordinator: SyncCoordinator
    
    private init() {
        operations = CloudKitOperations()
        offlineQueue = OfflineQueue()
        reconciler = ReconciliationEngine()
        networkMonitor = NetworkMonitor()
        syncCoordinator = SyncCoordinator(
            operations: operations,
            offlineQueue: offlineQueue,
            reconciler: reconciler,
            networkMonitor: networkMonitor
        )
        
        setupBindings()
    }
    
    private func setupBindings() {
        // Bind published properties to components
        syncCoordinator.$syncStatus
            .assign(to: &$syncStatus)
        
        networkMonitor.$isConnected
            .assign(to: &$isConnected)
        
        offlineQueue.$offlineQueueCount
            .assign(to: &$offlineQueueCount)
        
        // Setup network state change handler
        networkMonitor.setConnectionStateChangeHandler { [weak self] in
            Task {
                if self?.isConnected == true {
                    // Coming back online
                    if self?.syncCoordinator.syncStatus != .syncing {
                        await self?.syncCoordinator.handleReconnection()
                    }
                } else {
                    // Going offline
                    print("📵 [CloudKit] Network disconnected - operations will be queued")
                }
            }
        }
    }
    
    // MARK: - Public API
    
    /// Push a clipboard item to iCloud with offline queue support
    func pushItem(_ item: ClipboardItem) async throws {
        guard let itemId = item.id else {
            throw CloudKitError.invalidData("Item missing ID")
        }
        
        // If offline, queue the operation
        if !isConnected {
            offlineQueue.queuePushOperation(
                itemId: itemId,
                contentHash: item.contentHash ?? ""
            )
            
            item.iCloudSyncStatus = SyncStatus.local.rawValue
            try PersistenceController.shared.container.viewContext.save()
            
            print("📤 [Offline Queue] Queued push for item: \(itemId)")
            return
        }
        
        try await operations.pushItemDirectly(item)
    }
    
    /// Pull all items from iCloud
    func pullAllItems() async throws -> [ClipboardItem] {
        guard isConnected else {
            throw CloudKitError.notConnected
        }
        
        return try await operations.pullAllItems()
    }
    
    /// Delete an item from iCloud with offline queue support
    func deleteItem(id: UUID) async throws {
        // If offline, queue the operation
        if !isConnected {
            offlineQueue.queueDeleteOperation(itemId: id)
            
            // Mark as deleted locally
            if let localItem = reconciler.findLocalItem(with: id) {
                localItem.markedAsDeleted = true
                localItem.lastModified = Date()
                try PersistenceController.shared.container.viewContext.save()
            }
            
            print("📤 [Offline Queue] Queued deletion for item: \(id)")
            return
        }
        
        try await operations.deleteItem(id: id)
    }
    
    /// Subscribe to CloudKit changes for real-time updates
    func subscribeToChanges() async throws {
        try await operations.subscribeToChanges()
    }
    
    /// Handle remote notification from CloudKit
    func handleRemoteNotification(_ notification: CKNotification) async {
        guard let queryNotification = notification as? CKQueryNotification else { return }
        
        print("📡 [CloudKit] Received remote notification: \(queryNotification.queryNotificationReason)")
        
        // Trigger a sync when we receive changes
        await syncFromCloud()
    }
    
    /// Sync from cloud
    func syncFromCloud() async {
        await syncCoordinator.syncFromCloud()
    }
    
    /// Force a full reconciliation sync
    func forceFullSync() async {
        await syncCoordinator.forceFullSync()
    }
    
    /// Update sync frequency (useful for testing or performance tuning)
    func updateSyncInterval(_ interval: TimeInterval) {
        syncCoordinator.updateSyncInterval(interval)
    }
    
    /// Get offline queue status
    func getOfflineQueueStatus() -> (count: Int, oldestOperation: Date?) {
        return offlineQueue.getQueueStatus()
    }
}
