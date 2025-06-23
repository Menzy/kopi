//
//  IDResolver.swift
//  kopi
//
//  Created by AI Assistant on 19/06/2025.
//

import Foundation
import CoreData
import CloudKit

enum IDResolutionResult {
    case resolved(canonicalID: UUID, initiatingDevice: String)
    case conflicted(localID: UUID, remoteID: UUID, reason: String)
    case pending(temporaryID: UUID)
    case failed(error: Error)
}

enum ResolutionStrategy {
    case timestampPriority    // Older item wins
    case devicePriority       // Specific device takes precedence
    case contentHash         // Use content hash as tiebreaker
    case userChoice          // Require user intervention
}

struct IDConflict {
    let localItem: ClipboardItem
    let remoteItem: ClipboardItem
    let conflictReason: String
    let suggestedResolution: ResolutionStrategy
    let confidence: Double
}

class IDResolver: ObservableObject {
    static let shared = IDResolver()
    
    private let persistenceController = PersistenceController.shared
    private let deviceManager = DeviceManager.shared
    private let correlator = ClipboardCorrelator.shared
    
    // Resolution configuration
    private let resolutionTimeWindow: TimeInterval = 60.0 // 1 minute window for conflicts
    private let maxResolutionAttempts = 3
    private let batchSize = 10
    
    // Track resolution state
    @Published var isResolving = false
    @Published var pendingResolutions: [UUID] = []
    @Published var conflictedItems: [IDConflict] = []
    
    private var resolutionQueue = DispatchQueue(label: "com.kopi.idresolver", qos: .userInitiated)
    private var resolutionTimer: Timer?
    
    private init() {
        setupPeriodicResolution()
        setupCloudKitNotifications()
    }
    
    // MARK: - Public API
    
    /// Resolve canonical ID for a clipboard item, handling conflicts intelligently
    func resolveCanonicalID(for item: ClipboardItem) async -> IDResolutionResult {
        guard let content = item.content else {
            return .failed(error: IDResolverError.invalidContent)
        }
        
        print("🔍 [IDResolver] Resolving canonical ID for item: \(item.id?.uuidString ?? "unknown")")
        print("   📄 Content: \(content.prefix(50))")
        print("   📱 Current Device: \(deviceManager.getDeviceID())")
        
        // Check if item already has a canonical ID
        if let existingCanonicalID = item.canonicalID,
           !item.isTemporary {
            print("✅ [IDResolver] Item already has canonical ID: \(existingCanonicalID.uuidString)")
            return .resolved(canonicalID: existingCanonicalID, initiatingDevice: item.initiatingDevice ?? deviceManager.getDeviceID())
        }
        
        // Search for matching items across all devices
        let matchingItems = await findMatchingItems(content: content, timestamp: item.timestamp ?? Date())
        
        if matchingItems.isEmpty {
            // No conflicts - assign new canonical ID
            let newCanonicalID = deviceManager.createCanonicalID()
            await updateItemCanonicalID(item, canonicalID: newCanonicalID, initiatingDevice: deviceManager.getDeviceID())
            
            print("🆕 [IDResolver] Assigned new canonical ID: \(newCanonicalID.uuidString)")
            return .resolved(canonicalID: newCanonicalID, initiatingDevice: deviceManager.getDeviceID())
        }
        
        // Handle conflicts using smart resolution
        return await handleIDConflicts(localItem: item, matchingItems: matchingItems)
    }
    
    /// Batch resolve multiple items for efficiency
    func batchResolveCanonicalIDs(for items: [ClipboardItem]) async {
        guard !items.isEmpty else { return }
        
        print("📦 [IDResolver] Starting batch resolution for \(items.count) items")
        
        await MainActor.run {
            isResolving = true
            pendingResolutions = items.compactMap { $0.id }
        }
        
        let chunks = items.chunked(into: batchSize)
        
        for chunk in chunks {
            await withTaskGroup(of: Void.self) { group in
                for item in chunk {
                    group.addTask {
                        let result = await self.resolveCanonicalID(for: item)
                        await self.handleResolutionResult(result, for: item)
                    }
                }
            }
        }
        
        await MainActor.run {
            isResolving = false
            pendingResolutions.removeAll()
        }
        
        print("✅ [IDResolver] Batch resolution completed")
    }
    
    /// Force resolve all temporary items
    func resolveAllTemporaryItems() async {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isTemporary == YES")
        
        do {
            let temporaryItems = try context.fetch(fetchRequest)
            if !temporaryItems.isEmpty {
                print("🔄 [IDResolver] Found \(temporaryItems.count) temporary items to resolve")
                await batchResolveCanonicalIDs(for: temporaryItems)
            }
        } catch {
            print("❌ [IDResolver] Error fetching temporary items: \(error)")
        }
    }
    
    /// Resolve conflict with specific strategy
    func resolveConflict(_ conflict: IDConflict, using strategy: ResolutionStrategy) async {
        print("⚖️ [IDResolver] Resolving conflict using strategy: \(strategy)")
        
        let (winningItem, losingItem) = determineWinningItem(conflict: conflict, strategy: strategy)
        
        // Update losing item to use winning item's canonical ID
        await updateItemCanonicalID(
            losingItem,
            canonicalID: winningItem.canonicalID ?? deviceManager.createCanonicalID(),
            initiatingDevice: winningItem.initiatingDevice ?? deviceManager.getDeviceID()
        )
        
        // Remove from conflicts list
        await MainActor.run {
            conflictedItems.removeAll { $0.localItem.id == conflict.localItem.id }
        }
        
        print("✅ [IDResolver] Conflict resolved - using canonical ID: \(winningItem.canonicalID?.uuidString ?? "unknown")")
    }
    
    // MARK: - Private Methods
    
    private func findMatchingItems(content: String, timestamp: Date) async -> [ClipboardItem] {
        let context = persistenceController.container.newBackgroundContext()
        let fetchRequest: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        
        // Look for items with similar content within time window
        let timeWindow = Date().addingTimeInterval(-resolutionTimeWindow)
        fetchRequest.predicate = NSPredicate(
            format: "content == %@ AND timestamp >= %@ AND initiatingDevice != %@",
            content,
            timeWindow as NSDate,
            deviceManager.getDeviceID()
        )
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.timestamp, ascending: true)]
        
        do {
            return try context.fetch(fetchRequest)
        } catch {
            print("❌ [IDResolver] Error finding matching items: \(error)")
            return []
        }
    }
    
    private func handleIDConflicts(localItem: ClipboardItem, matchingItems: [ClipboardItem]) async -> IDResolutionResult {
        // Simple case: only one match
        if matchingItems.count == 1 {
            let matchingItem = matchingItems[0]
            
            if let canonicalID = matchingItem.canonicalID {
                await updateItemCanonicalID(
                    localItem,
                    canonicalID: canonicalID,
                    initiatingDevice: matchingItem.initiatingDevice ?? deviceManager.getDeviceID()
                )
                
                print("🔗 [IDResolver] Resolved using matching item's canonical ID: \(canonicalID.uuidString)")
                return .resolved(canonicalID: canonicalID, initiatingDevice: matchingItem.initiatingDevice ?? deviceManager.getDeviceID())
            }
        }
        
        // Complex case: multiple matches - use intelligent resolution
        let bestMatch = selectBestMatch(from: matchingItems)
        
        if let bestMatch = bestMatch,
           let canonicalID = bestMatch.canonicalID {
            await updateItemCanonicalID(
                localItem,
                canonicalID: canonicalID,
                initiatingDevice: bestMatch.initiatingDevice ?? deviceManager.getDeviceID()
            )
            
            print("🎯 [IDResolver] Resolved using best match canonical ID: \(canonicalID.uuidString)")
            return .resolved(canonicalID: canonicalID, initiatingDevice: bestMatch.initiatingDevice ?? deviceManager.getDeviceID())
        }
        
        // Conflict requires manual resolution
        let conflict = IDConflict(
            localItem: localItem,
            remoteItem: matchingItems.first!,
            conflictReason: "Multiple matching items found",
            suggestedResolution: .timestampPriority,
            confidence: 0.8
        )
        
        await MainActor.run {
            conflictedItems.append(conflict)
        }
        
        print("⚠️ [IDResolver] Conflict detected - requires resolution")
        return .conflicted(
            localID: localItem.id ?? UUID(),
            remoteID: matchingItems.first?.id ?? UUID(),
            reason: "Multiple matching items found"
        )
    }
    
    private func selectBestMatch(from items: [ClipboardItem]) -> ClipboardItem? {
        // Priority: Oldest timestamp (first to create canonical ID)
        return items.min { item1, item2 in
            (item1.timestamp ?? Date.distantFuture) < (item2.timestamp ?? Date.distantFuture)
        }
    }
    
    private func determineWinningItem(conflict: IDConflict, strategy: ResolutionStrategy) -> (winner: ClipboardItem, loser: ClipboardItem) {
        switch strategy {
        case .timestampPriority:
            let localTime = conflict.localItem.timestamp ?? Date.distantFuture
            let remoteTime = conflict.remoteItem.timestamp ?? Date.distantFuture
            return localTime < remoteTime 
                ? (conflict.localItem, conflict.remoteItem)
                : (conflict.remoteItem, conflict.localItem)
                
        case .devicePriority:
            // Prefer Mac over iOS for consistency
            let localDevice = conflict.localItem.initiatingDevice ?? ""
            return localDevice.contains("mac") 
                ? (conflict.localItem, conflict.remoteItem)
                : (conflict.remoteItem, conflict.localItem)
                
        case .contentHash:
            // Use content hash as tiebreaker
            let localHash = conflict.localItem.content?.hash ?? 0
            let remoteHash = conflict.remoteItem.content?.hash ?? 0
            return localHash < remoteHash
                ? (conflict.localItem, conflict.remoteItem)
                : (conflict.remoteItem, conflict.localItem)
                
        case .userChoice:
            // Default to timestamp for now - UI would handle user choice
            return determineWinningItem(conflict: conflict, strategy: .timestampPriority)
        }
    }
    
    private func updateItemCanonicalID(_ item: ClipboardItem, canonicalID: UUID, initiatingDevice: String) async {
        let context = persistenceController.container.viewContext
        
        await context.perform {
            item.canonicalID = canonicalID
            item.initiatingDevice = initiatingDevice
            item.isTemporary = false
            
            do {
                try context.save()
                print("💾 [IDResolver] Updated item canonical ID: \(canonicalID.uuidString)")
            } catch {
                print("❌ [IDResolver] Error updating canonical ID: \(error)")
            }
        }
    }
    
    private func handleResolutionResult(_ result: IDResolutionResult, for item: ClipboardItem) async {
        await MainActor.run {
            if let itemID = item.id {
                pendingResolutions.removeAll { $0 == itemID }
            }
        }
        
        switch result {
        case .resolved(let canonicalID, let initiatingDevice):
            print("✅ [IDResolver] Successfully resolved: \(canonicalID.uuidString) from \(initiatingDevice)")
            
        case .conflicted(let localID, let remoteID, let reason):
            print("⚠️ [IDResolver] Conflict detected between \(localID.uuidString) and \(remoteID.uuidString): \(reason)")
            
        case .pending(let temporaryID):
            print("⏳ [IDResolver] Resolution pending for: \(temporaryID.uuidString)")
            
        case .failed(let error):
            print("❌ [IDResolver] Resolution failed: \(error)")
        }
    }
    
    private func setupPeriodicResolution() {
        resolutionTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task {
                await self?.resolveAllTemporaryItems()
            }
        }
    }
    
    private func setupCloudKitNotifications() {
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistenceController.container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.resolveAllTemporaryItems()
            }
        }
    }
}

// MARK: - Supporting Types and Extensions

enum IDResolverError: Error, LocalizedError {
    case invalidContent
    case noMatchingItems
    case conflictUnresolved
    case cloudKitUnavailable
    
    var errorDescription: String? {
        switch self {
        case .invalidContent:
            return "Invalid clipboard content"
        case .noMatchingItems:
            return "No matching items found"
        case .conflictUnresolved:
            return "ID conflict could not be resolved"
        case .cloudKitUnavailable:
            return "CloudKit is not available"
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
} 