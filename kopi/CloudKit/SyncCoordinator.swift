//
//  SyncCoordinator.swift
//  kopi
//
//  Created by Wan Menzy on 20/06/2025.
//

import Foundation

@MainActor
class SyncCoordinator: ObservableObject {
    @Published var syncStatus: SyncStatus = .local
    
    private var syncTimer: Timer?
    private var lastFullSyncDate: Date?
    
    private let operations: CloudKitOperations
    private let offlineQueue: OfflineQueue
    private let reconciler: ReconciliationEngine
    private let networkMonitor: NetworkMonitor
    
    init(operations: CloudKitOperations, offlineQueue: OfflineQueue, reconciler: ReconciliationEngine, networkMonitor: NetworkMonitor) {
        self.operations = operations
        self.offlineQueue = offlineQueue
        self.reconciler = reconciler
        self.networkMonitor = networkMonitor
        
        startPeriodicSync()
    }
    
    // MARK: - Sync Operations
    
    /// Enhanced sync with offline queue processing
    func syncFromCloud() async {
        // Process offline queue first if connected
        if networkMonitor.isConnected {
            await processOfflineQueue()
        }
        
        // Then perform regular sync
        do {
            syncStatus = .syncing
            let cloudItems = try await operations.pullAllItems()
            await reconciler.reconcileItems(cloudItems)
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
    
    private func performFullReconciliationSync() async {
        do {
            syncStatus = .syncing
            
            // Pull all items from cloud for full reconciliation
            let cloudItems = try await operations.pullAllItems()
            
            // Perform enhanced reconciliation
            await reconciler.reconcileItems(cloudItems)
            
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
    
    // MARK: - Offline Queue Processing
    
    private func processOfflineQueue() async {
        guard networkMonitor.isConnected else { return }
        
        await offlineQueue.processQueuedOperations(using: operations)
    }
    
    // MARK: - Reconnection Handling
    
    func handleReconnection() async {
        print("🔄 [Reconnection] Handling reconnection to iCloud")
        
        // 1. Process offline queue first
        await processOfflineQueue()
        
        // 2. Perform full reconciliation sync
        await performFullReconciliationSync()
        
        print("✅ [Reconnection] Reconnection handling complete")
    }
    
    // MARK: - Periodic Sync Management
    
    private func startPeriodicSync() {
        // Start periodic sync every 10 seconds for responsive deletion detection
        syncTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task {
                await self?.syncFromCloud()
            }
        }
        
        // Add timer to run loop to ensure it continues running
        if let timer = syncTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        
        print("🔄 [macOS CloudKit] Started periodic sync - checking iCloud every 10 seconds")
    }
    
    private func stopPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = nil
        print("⏹️ [macOS CloudKit] Stopped periodic sync")
    }
    
    /// Update sync frequency (useful for testing or performance tuning)
    func updateSyncInterval(_ interval: TimeInterval) {
        stopPeriodicSync()
        
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task {
                await self?.syncFromCloud()
            }
        }
        
        if let timer = syncTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        
        print("🔄 [macOS CloudKit] Updated sync interval to \(interval) seconds")
    }
    
    deinit {
        syncTimer?.invalidate()
        syncTimer = nil
    }
}
