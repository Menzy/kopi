//
//  CloudKitManager.swift
//  kopi iOS
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
    
    // Components
    private let operations: CloudKitOperations
    private let reconciler: ReconciliationEngine
    private let networkMonitor: NetworkMonitor
    
    // iOS-specific properties
    private var lastFullSyncDate: Date?
    
    private init() {
        operations = CloudKitOperations()
        reconciler = ReconciliationEngine()
        networkMonitor = NetworkMonitor()
        
        setupBindings()
    }
    
    private func setupBindings() {
        // Bind published properties to components
        networkMonitor.$isConnected
            .assign(to: &$isConnected)
        
        // Setup network state change handler
        networkMonitor.setConnectionStateChangeHandler { [weak self] in
            Task {
                if self?.isConnected == true {
                    // Coming back online - perform sync
                    await self?.syncFromCloud()
                } else {
                    // Going offline
                    print("📵 [iOS CloudKit] Network disconnected")
                }
            }
        }
    }
    
    // MARK: - Public API
    
    /// Pull all items from iCloud
    func pullAllItems() async throws -> [ClipboardItem] {
        guard isConnected else {
            throw CloudKitError.notConnected
        }
        
        return try await operations.pullAllItems()
    }
    
    /// Delete an item from iCloud (iOS can delete even though it's read-only for creation)
    func deleteItem(id: UUID) async throws {
        guard isConnected else {
            print("📵 [iOS CloudKit] Offline - cannot delete from iCloud: \(id)")
            throw CloudKitError.notConnected
        }
        
        try await operations.deleteItem(id: id)
    }
    
    /// iOS does not create subscriptions - only macOS handles CloudKit subscriptions
    /// This is a no-op function to maintain compatibility
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
    
    /// iOS-specific sync - only pulls from iCloud, never pushes
    func syncFromCloud() async {
        // iOS is purely a sync client - only pulls from iCloud
        do {
            syncStatus = .syncing
            let cloudItems = try await operations.pullAllItems()
            await reconciler.reconcileItems(cloudItems)
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
    
    private func performFullReconciliationSync() async {
        do {
            syncStatus = .syncing
            
            // Pull all items from cloud for full reconciliation
            let cloudItems = try await operations.pullAllItems()
            
            // Perform enhanced reconciliation
            await reconciler.reconcileItems(cloudItems)
            
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
    
    /// Get offline queue status (always returns 0 for iOS since no pushing)
    func getOfflineQueueStatus() -> (count: Int, oldestOperation: Date?) {
        return (count: 0, oldestOperation: nil)
    }
}
