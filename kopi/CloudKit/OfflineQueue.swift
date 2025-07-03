//
//  OfflineQueue.swift
//  kopi
//
//  Created by Wan Menzy on 20/06/2025.
//

import Foundation

@MainActor
class OfflineQueue: ObservableObject {
    @Published var offlineQueueCount: Int = 0
    
    private var offlineOperationQueue: [OfflineOperation] = []
    private let offlineQueueLock = NSLock()
    
    // MARK: - Offline Operation Types
    
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
    
    init() {
        loadOfflineQueue()
    }
    
    // MARK: - Queue Management
    
    func queuePushOperation(itemId: UUID, contentHash: String) {
        let operation = OfflineOperation.pushItem(
            itemId: itemId,
            contentHash: contentHash,
            timestamp: Date()
        )
        queueOperation(operation)
    }
    
    func queueDeleteOperation(itemId: UUID) {
        let operation = OfflineOperation.deleteItem(itemId: itemId, timestamp: Date())
        queueOperation(operation)
    }
    
    func queueUpdateOperation(itemId: UUID, contentHash: String) {
        let operation = OfflineOperation.updateItem(
            itemId: itemId,
            contentHash: contentHash,
            timestamp: Date()
        )
        queueOperation(operation)
    }
    
    private func queueOperation(_ operation: OfflineOperation) {
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
    
    private func getOperationsToProcess() -> [OfflineOperation] {
        offlineQueueLock.lock()
        defer { offlineQueueLock.unlock() }
        return offlineOperationQueue
    }
    
    private func removeProcessedOperations(_ processedOperations: [OfflineOperation]) {
        offlineQueueLock.lock()
        defer { offlineQueueLock.unlock() }
        
        for processedOp in processedOperations {
            offlineOperationQueue.removeAll { $0.itemId == processedOp.itemId && $0.timestamp == processedOp.timestamp }
        }
        
        offlineQueueCount = offlineOperationQueue.count
        saveOfflineQueue()
    }
    
    func getQueueStatus() -> (count: Int, oldestOperation: Date?) {
        offlineQueueLock.lock()
        defer { offlineQueueLock.unlock() }
        
        let count = offlineOperationQueue.count
        let oldestDate = offlineOperationQueue.min(by: { $0.timestamp < $1.timestamp })?.timestamp
        
        return (count: count, oldestOperation: oldestDate)
    }
    
    // MARK: - Persistence
    
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
    
    // MARK: - Process Operations
    
    private func processOperations(using operations: CloudKitOperations) async -> [OfflineOperation] {
        let operationsToProcess = getOperationsToProcess()
        guard !operationsToProcess.isEmpty else { return [] }
        
        print("🔄 [Offline Queue] Processing \(operationsToProcess.count) queued operations")
        
        var processedOperations: [OfflineOperation] = []
        
        for operation in operationsToProcess.sorted(by: { $0.timestamp < $1.timestamp }) {
            do {
                switch operation {
                case .pushItem(let itemId, _, _):
                    if let item = operations.findLocalItem(with: itemId) {
                        try await operations.pushItemDirectly(item)
                    }
                case .deleteItem(let itemId, _):
                    try await operations.deleteItem(id: itemId)
                case .updateItem(let itemId, _, _):
                    if let item = operations.findLocalItem(with: itemId) {
                        try await operations.pushItemDirectly(item)
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
        
        print("🔄 [Offline Queue] Processed \(processedOperations.count) operations, \(offlineQueueCount) remaining")
        return processedOperations
    }
    
    func processQueuedOperations(using operations: CloudKitOperations) async {
        let processedOperations = await processOperations(using: operations)
        
        // Remove successfully processed operations
        if !processedOperations.isEmpty {
            removeProcessedOperations(processedOperations)
        }
    }
}
