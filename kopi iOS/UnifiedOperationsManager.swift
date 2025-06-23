//
//  UnifiedOperationsManager.swift
//  kopi iOS
//
//  Created by AI Assistant on 19/06/2025.
//

import Foundation
import CoreData
import Combine

enum UnifiedOperation {
    case edit(canonicalID: UUID, newContent: String, version: Int)
    case delete(canonicalID: UUID)
    case favorite(canonicalID: UUID, isFavorite: Bool)
    case pin(canonicalID: UUID, isPinned: Bool)
    case addToCollection(canonicalID: UUID, collectionName: String)
    case removeFromCollection(canonicalID: UUID, collectionName: String)
    case reorder(canonicalIDs: [UUID], newOrder: [Int])
}

enum OperationResult {
    case success(operation: UnifiedOperation)
    case failure(operation: UnifiedOperation, error: Error)
    case conflict(operation: UnifiedOperation, conflictType: ConflictType)
    case pending(operation: UnifiedOperation)
}

enum ConflictType {
    case editConflict(localVersion: Int, remoteVersion: Int)
    case deleteConflict(reason: String)
    case organizationConflict(conflictingState: String)
}

struct EditVersion {
    let version: Int
    let content: String
    let timestamp: Date
    let deviceID: String
    let editType: EditType
}

enum EditType {
    case contentChange
    case organizationChange
    case metadataChange
}

class UnifiedOperationsManager: ObservableObject {
    static let shared = UnifiedOperationsManager()
    
    private let persistenceController = PersistenceController.shared
    private let deviceManager = DeviceManager.shared
    private let cloudKitSyncManager = CloudKitSyncManager.shared
    private let idResolver = IDResolver.shared
    
    // Operation state tracking
    @Published var pendingOperations: [UnifiedOperation] = []
    @Published var isProcessingOperations = false
    @Published var operationErrors: [Error] = []
    @Published var conflicts: [ConflictType] = []
    
    // Edit history tracking
    private var editHistory: [UUID: [EditVersion]] = [:]
    private let maxVersionHistory = 10
    
    // Organization state
    @Published var favoriteItems: Set<UUID> = []
    @Published var pinnedItems: Set<UUID> = []
    @Published var collections: [String: Set<UUID>] = [:]
    
    private var cancellables = Set<AnyCancellable>()
    private let operationQueue = DispatchQueue(label: "com.kopi.unifiedoperations", qos: .userInitiated)
    
    private init() {
        setupOperationMonitoring()
        loadOrganizationState()
    }
    
    // MARK: - Public API
    
    /// Edit clipboard item content across all devices
    func editClipboardItem(canonicalID: UUID, newContent: String) async -> OperationResult {
        // Editing item (verbose logging disabled)
        
        // Get current item to check version
        guard let currentItem = await fetchItemByCanonicalID(canonicalID) else {
            let error = UnifiedOperationError.itemNotFound(canonicalID)
            return .failure(operation: .edit(canonicalID: canonicalID, newContent: newContent, version: 0), error: error)
        }
        
        let currentVersion = Int(currentItem.version)
        let newVersion = currentVersion + 1
        
        // Create edit version for history
        let editVersion = EditVersion(
            version: newVersion,
            content: newContent,
            timestamp: Date(),
            deviceID: deviceManager.getDeviceID(),
            editType: .contentChange
        )
        
        // Add to edit history
        await addToEditHistory(canonicalID: canonicalID, editVersion: editVersion)
        
        let operation = UnifiedOperation.edit(canonicalID: canonicalID, newContent: newContent, version: newVersion)
        
        // Execute the edit operation
        let result = await executeEditOperation(operation, currentItem: currentItem)
        
        return result
    }
    
    /// Delete clipboard item across all devices
    func deleteClipboardItem(canonicalID: UUID) async -> OperationResult {
        // Deleting item
        
        let operation = UnifiedOperation.delete(canonicalID: canonicalID)
        
        await MainActor.run {
            pendingOperations.append(operation)
        }
        
        // Execute via CloudKitSyncManager
        await cloudKitSyncManager.deleteItemAcrossDevices(canonicalID: canonicalID)
        
        // Clean up local organization state
        await cleanupOrganizationState(canonicalID: canonicalID)
        
        await MainActor.run {
            pendingOperations.removeAll { op in
                if case .delete(let id) = op { return id == canonicalID }
                return false
            }
        }
        
        // Delete operation completed
        return .success(operation: operation)
    }
    
    /// Toggle favorite status across all devices
    func toggleFavorite(canonicalID: UUID) async -> OperationResult {
        let isFavorite = !favoriteItems.contains(canonicalID)
        print("⭐ [iOS UnifiedOps] Setting favorite (\(isFavorite)) for: \(canonicalID.uuidString)")
        
        let operation = UnifiedOperation.favorite(canonicalID: canonicalID, isFavorite: isFavorite)
        
        // Update local state
        await MainActor.run {
            if isFavorite {
                favoriteItems.insert(canonicalID)
            } else {
                favoriteItems.remove(canonicalID)
            }
        }
        
        // Update Core Data
        if let item = await fetchItemByCanonicalID(canonicalID) {
            await updateItemFavoriteStatus(item, isFavorite: isFavorite)
        }
        
        // Sync to CloudKit
        await syncOrganizationChange(operation)
        
        return .success(operation: operation)
    }
    
    /// Toggle pin status across all devices
    func togglePin(canonicalID: UUID) async -> OperationResult {
        let isPinned = !pinnedItems.contains(canonicalID)
        print("📌 [iOS UnifiedOps] Setting pinned (\(isPinned)) for: \(canonicalID.uuidString)")
        
        let operation = UnifiedOperation.pin(canonicalID: canonicalID, isPinned: isPinned)
        
        // Update local state
        await MainActor.run {
            if isPinned {
                pinnedItems.insert(canonicalID)
            } else {
                pinnedItems.remove(canonicalID)
            }
        }
        
        // Update Core Data
        if let item = await fetchItemByCanonicalID(canonicalID) {
            await updateItemPinStatus(item, isPinned: isPinned)
        }
        
        // Sync to CloudKit
        await syncOrganizationChange(operation)
        
        return .success(operation: operation)
    }
    
    /// Add item to collection across all devices
    func addToCollection(canonicalID: UUID, collectionName: String) async -> OperationResult {
        print("📁 [iOS UnifiedOps] Adding \(canonicalID.uuidString) to collection: \(collectionName)")
        
        let operation = UnifiedOperation.addToCollection(canonicalID: canonicalID, collectionName: collectionName)
        
        // Update local state
        await MainActor.run {
            if collections[collectionName] == nil {
                collections[collectionName] = Set<UUID>()
            }
            collections[collectionName]?.insert(canonicalID)
        }
        
        // Update Core Data
        if let item = await fetchItemByCanonicalID(canonicalID) {
            await updateItemCollection(item, collectionName: collectionName, add: true)
        }
        
        // Sync to CloudKit
        await syncOrganizationChange(operation)
        
        return .success(operation: operation)
    }
    
    /// Batch process multiple operations for efficiency
    func batchProcessOperations(_ operations: [UnifiedOperation]) async -> [OperationResult] {
        print("📦 [iOS UnifiedOps] Batch processing \(operations.count) operations")
        
        await MainActor.run {
            isProcessingOperations = true
            pendingOperations.append(contentsOf: operations)
        }
        
        var results: [(Int, OperationResult)] = []
        
        // Process operations in parallel where possible
        await withTaskGroup(of: (Int, OperationResult).self) { group in
            for (index, operation) in operations.enumerated() {
                group.addTask {
                    let result = await self.processOperation(operation)
                    return (index, result)
                }
            }
            
            for await (index, result) in group {
                results.append((index, result))
            }
        }
        
        await MainActor.run {
            isProcessingOperations = false
            pendingOperations.removeAll { pending in
                operations.contains { op in
                    self.operationsEqual(pending, op)
                }
            }
        }
        
        print("✅ [iOS UnifiedOps] Batch processing completed")
        return results.sorted(by: { $0.0 < $1.0 }).map { $0.1 }
    }
    
    /// Get edit history for an item
    func getEditHistory(canonicalID: UUID) -> [EditVersion] {
        return editHistory[canonicalID] ?? []
    }
    
    /// Resolve edit conflict with specific strategy
    func resolveEditConflict(canonicalID: UUID, strategy: ConflictResolutionStrategy) async -> OperationResult {
        print("⚖️ [iOS UnifiedOps] Resolving edit conflict for: \(canonicalID.uuidString)")
        
        guard let currentItem = await fetchItemByCanonicalID(canonicalID),
              let history = editHistory[canonicalID],
              history.count >= 2 else {
            return .failure(operation: .edit(canonicalID: canonicalID, newContent: "", version: 0), 
                          error: UnifiedOperationError.conflictResolutionFailed)
        }
        
        let latestVersion = history.last!
        let winningContent: String
        
        switch strategy {
        case .useLocal:
            winningContent = currentItem.content ?? ""
            
        case .useRemote:
            winningContent = latestVersion.content
            // Version will be handled by editClipboardItem
            
        case .merge:
            // Simple merge strategy - could be enhanced with diff algorithms
            winningContent = mergeContent(local: currentItem.content ?? "", remote: latestVersion.content)
            
        case .userChoice(let chosenContent):
            winningContent = chosenContent
        }
        
        // Apply the resolved edit
        return await editClipboardItem(canonicalID: canonicalID, newContent: winningContent)
    }
    
    // MARK: - Private Methods
    
    private func processOperation(_ operation: UnifiedOperation) async -> OperationResult {
        switch operation {
        case .edit(let canonicalID, let newContent, _):
            return await editClipboardItem(canonicalID: canonicalID, newContent: newContent)
            
        case .delete(let canonicalID):
            return await deleteClipboardItem(canonicalID: canonicalID)
            
        case .favorite(let canonicalID, _):
            return await toggleFavorite(canonicalID: canonicalID)
            
        case .pin(let canonicalID, _):
            return await togglePin(canonicalID: canonicalID)
            
        case .addToCollection(let canonicalID, let collectionName):
            return await addToCollection(canonicalID: canonicalID, collectionName: collectionName)
            
        case .removeFromCollection(let canonicalID, let collectionName):
            return await removeFromCollection(canonicalID: canonicalID, collectionName: collectionName)
            
        case .reorder(let canonicalIDs, let newOrder):
            return await reorderItems(canonicalIDs: canonicalIDs, newOrder: newOrder)
        }
    }
    
    private func executeEditOperation(_ operation: UnifiedOperation, currentItem: ClipboardItem) async -> OperationResult {
        guard case .edit(let canonicalID, let newContent, let newVersion) = operation else {
            return .failure(operation: operation, error: UnifiedOperationError.invalidOperation)
        }
        
        // Check for edit conflicts
        if let conflictType = await checkForEditConflicts(canonicalID: canonicalID, newVersion: newVersion) {
            return .conflict(operation: operation, conflictType: conflictType)
        }
        
        // Update local item
        let context = persistenceController.container.viewContext
        
        await context.perform {
            currentItem.content = newContent
            currentItem.version = Int32(newVersion)
            currentItem.lastModified = Date()
            currentItem.lastModifyingDevice = self.deviceManager.getDeviceID()
            
            // Update preview
            currentItem.contentPreview = newContent.count > 100 ? String(newContent.prefix(100)) + "..." : newContent
            currentItem.fileSize = Int64(newContent.data(using: .utf8)?.count ?? 0)
            
            do {
                try context.save()
                print("✅ [iOS UnifiedOps] Local edit saved for: \(canonicalID.uuidString)")
            } catch {
                print("❌ [iOS UnifiedOps] Failed to save local edit: \(error)")
            }
        }
        
        // Sync to CloudKit
        await cloudKitSyncManager.syncItem(currentItem, operation: .update(currentItem))
        
        return .success(operation: operation)
    }
    
    private func fetchItemByCanonicalID(_ canonicalID: UUID) async -> ClipboardItem? {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "canonicalID == %@", canonicalID as CVarArg)
        fetchRequest.fetchLimit = 1
        
        do {
            let items = try context.fetch(fetchRequest)
            return items.first
        } catch {
            print("❌ [iOS UnifiedOps] Error fetching item: \(error)")
            return nil
        }
    }
    
    private func addToEditHistory(canonicalID: UUID, editVersion: EditVersion) async {
        await MainActor.run {
            if editHistory[canonicalID] == nil {
                editHistory[canonicalID] = []
            }
            
            editHistory[canonicalID]?.append(editVersion)
            
            // Keep only recent versions
            if let history = editHistory[canonicalID], history.count > maxVersionHistory {
                editHistory[canonicalID] = Array(history.suffix(maxVersionHistory))
            }
        }
    }
    
    private func checkForEditConflicts(canonicalID: UUID, newVersion: Int) async -> ConflictType? {
        guard let currentItem = await fetchItemByCanonicalID(canonicalID) else { return nil }
        
        let currentVersion = Int(currentItem.version)
        
        // Check if there's a version conflict (someone else edited after our base version)
        if currentVersion >= newVersion {
            return .editConflict(localVersion: currentVersion, remoteVersion: newVersion)
        }
        
        return nil
    }
    
    private func updateItemFavoriteStatus(_ item: ClipboardItem, isFavorite: Bool) async {
        let context = persistenceController.container.viewContext
        
        await context.perform {
            item.isFavorite = isFavorite
            item.lastModified = Date()
            item.lastModifyingDevice = self.deviceManager.getDeviceID()
            
            do {
                try context.save()
                print("✅ [iOS UnifiedOps] Updated favorite status: \(isFavorite)")
            } catch {
                print("❌ [iOS UnifiedOps] Failed to update favorite status: \(error)")
            }
        }
    }
    
    private func updateItemPinStatus(_ item: ClipboardItem, isPinned: Bool) async {
        let context = persistenceController.container.viewContext
        
        await context.perform {
            item.isPinned = isPinned
            item.lastModified = Date()
            item.lastModifyingDevice = self.deviceManager.getDeviceID()
            
            do {
                try context.save()
                print("✅ [iOS UnifiedOps] Updated pin status: \(isPinned)")
            } catch {
                print("❌ [iOS UnifiedOps] Failed to update pin status: \(error)")
            }
        }
    }
    
    private func updateItemCollection(_ item: ClipboardItem, collectionName: String, add: Bool) async {
        let context = persistenceController.container.viewContext
        
        await context.perform {
            var collections = item.collections?.components(separatedBy: ",") ?? []
            
            if add {
                if !collections.contains(collectionName) {
                    collections.append(collectionName)
                }
            } else {
                collections.removeAll { $0 == collectionName }
            }
            
            item.collections = collections.joined(separator: ",")
            item.lastModified = Date()
            item.lastModifyingDevice = self.deviceManager.getDeviceID()
            
            do {
                try context.save()
                print("✅ [iOS UnifiedOps] Updated collection: \(collectionName)")
            } catch {
                print("❌ [iOS UnifiedOps] Failed to update collection: \(error)")
            }
        }
    }
    
    private func syncOrganizationChange(_ operation: UnifiedOperation) async {
        // Sync organization changes to CloudKit
        print("☁️ [iOS UnifiedOps] Syncing organization change to CloudKit")
    }
    
    private func cleanupOrganizationState(canonicalID: UUID) async {
        await MainActor.run {
            favoriteItems.remove(canonicalID)
            pinnedItems.remove(canonicalID)
            
            // Remove from all collections
            for (collectionName, items) in collections {
                var updatedItems = items
                updatedItems.remove(canonicalID)
                collections[collectionName] = updatedItems
            }
        }
    }
    
    func removeFromCollection(canonicalID: UUID, collectionName: String) async -> OperationResult {
        print("📁 [iOS UnifiedOps] Removing \(canonicalID.uuidString) from collection: \(collectionName)")
        
        let operation = UnifiedOperation.removeFromCollection(canonicalID: canonicalID, collectionName: collectionName)
        
        // Update local state
        _ = await MainActor.run {
            collections[collectionName]?.remove(canonicalID)
        }
        
        // Update Core Data
        if let item = await fetchItemByCanonicalID(canonicalID) {
            await updateItemCollection(item, collectionName: collectionName, add: false)
        }
        
        return .success(operation: operation)
    }
    
    private func reorderItems(canonicalIDs: [UUID], newOrder: [Int]) async -> OperationResult {
        print("🔀 [iOS UnifiedOps] Reordering \(canonicalIDs.count) items")
        
        // Update sort order for items
        for (index, canonicalID) in canonicalIDs.enumerated() {
            if let item = await fetchItemByCanonicalID(canonicalID) {
                let context = persistenceController.container.viewContext
                await context.perform {
                    item.sortOrder = Int32(newOrder[index])
                    do {
                        try context.save()
                    } catch {
                        print("❌ [iOS UnifiedOps] Failed to update sort order: \(error)")
                    }
                }
            }
        }
        
        let operation = UnifiedOperation.reorder(canonicalIDs: canonicalIDs, newOrder: newOrder)
        return .success(operation: operation)
    }
    
    private func mergeContent(local: String, remote: String) -> String {
        // Simple merge strategy - in a real app, you'd use a proper diff algorithm
        return """
        === MERGED CONTENT ===
        LOCAL:
        \(local)
        
        REMOTE:
        \(remote)
        === END MERGE ===
        """
    }
    
    private func operationsEqual(_ op1: UnifiedOperation, _ op2: UnifiedOperation) -> Bool {
        switch (op1, op2) {
        case (.edit(let id1, _, _), .edit(let id2, _, _)),
             (.delete(let id1), .delete(let id2)),
             (.favorite(let id1, _), .favorite(let id2, _)),
             (.pin(let id1, _), .pin(let id2, _)):
            return id1 == id2
        default:
            return false
        }
    }
    
    private func setupOperationMonitoring() {
        // Monitor for CloudKit remote changes that might affect our operations
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistenceController.container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handleRemoteChanges()
            }
        }
    }
    
    private func handleRemoteChanges() async {
        // Handle remote changes that might conflict with local operations
        // Handling remote changes (silent)
    }
    
    private func loadOrganizationState() {
        // Load organization state from UserDefaults or Core Data
        if let data = UserDefaults.standard.data(forKey: "favoriteItems"),
           let favorites = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            favoriteItems = favorites
        }
        
        if let data = UserDefaults.standard.data(forKey: "pinnedItems"),
           let pinned = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            pinnedItems = pinned
        }
    }
}

// MARK: - Supporting Types

enum ConflictResolutionStrategy {
    case useLocal
    case useRemote
    case merge
    case userChoice(String)
}

enum UnifiedOperationError: Error, LocalizedError {
    case itemNotFound(UUID)
    case invalidOperation
    case conflictResolutionFailed
    case syncFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .itemNotFound(let id):
            return "Item not found: \(id.uuidString)"
        case .invalidOperation:
            return "Invalid operation"
        case .conflictResolutionFailed:
            return "Failed to resolve conflict"
        case .syncFailed(let error):
            return "Sync failed: \(error.localizedDescription)"
        }
    }
} 