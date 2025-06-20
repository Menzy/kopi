//
//  Persistence.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Create sample clipboard items for preview
        let sampleItems = [
            ("Hello, World!", ContentType.text),
            ("https://www.apple.com", ContentType.url),
            ("Sample clipboard text for testing the preview", ContentType.text)
        ]
        
        for (content, type) in sampleItems {
            let item = ClipboardItem(context: viewContext)
            item.id = UUID()
            item.content = content
            item.contentType = type.rawValue
            item.contentPreview = content.count > 50 ? String(content.prefix(50)) + "..." : content
            item.timestamp = Date().addingTimeInterval(-Double.random(in: 0...3600))
            item.deviceOrigin = "macOS"

            item.isTransient = false
            item.isSensitive = false
            item.fileSize = Int64(content.data(using: .utf8)?.count ?? 0)
        }
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "kopi")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Configure CloudKit with proper migration strategy
            guard let description = container.persistentStoreDescriptions.first else {
                fatalError("Failed to retrieve a persistent store description.")
            }
            
            // Enable automatic lightweight migrations
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
            
            // Enable CloudKit sync
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            
            // Set a reasonable timeout for migrations
            description.setOption(30.0 as NSNumber, forKey: NSPersistentStoreTimeoutOption)
        }
        
        // Load persistent stores with proper error handling and migration support
        loadPersistentStoresWithMigration()
        
        // Configure the view context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Enable persistent history tracking
        do {
            try container.viewContext.setQueryGenerationFrom(.current)
        } catch {
            print("Failed to pin viewContext to the current generation: \(error)")
        }
        
        // Add CloudKit sync monitoring
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { notification in
            print("📡 [macOS] CloudKit remote change notification received")
        }
    }
    
    private func loadPersistentStoresWithMigration() {
        var migrationAttempted = false
        
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                print("📊 [macOS] Core Data error: \(error.localizedDescription)")
                print("📊 [macOS] Error details: \(error.userInfo)")
                
                // Check if this is a migration-related error
                if self.isMigrationError(error) && !migrationAttempted {
                    print("📊 [macOS] Migration error detected, attempting recovery...")
                    migrationAttempted = true
                    self.handleMigrationError(storeDescription: storeDescription, error: error)
                } else {
                    // For non-migration errors or if migration recovery failed
                    fatalError("Unresolved Core Data error: \(error), \(error.userInfo)")
                }
            } else {
                print("✅ [macOS] Core Data store loaded successfully")
                if let storeURL = storeDescription.url {
                    print("📊 [macOS] Store location: \(storeURL.path)")
                }
            }
        }
    }
    
    private func isMigrationError(_ error: NSError) -> Bool {
        // Check for common migration error codes
        let migrationErrorCodes: [Int] = [
            134140, // NSPersistentStoreIncompatibleVersionHashError
            134130, // NSMigrationMissingSourceModelError
            134110, // NSMigrationError
            134100, // NSCoreDataError
        ]
        
        return migrationErrorCodes.contains(error.code) || 
               error.localizedDescription.lowercased().contains("migration") ||
               error.localizedDescription.lowercased().contains("model")
    }
    
    private func handleMigrationError(storeDescription: NSPersistentStoreDescription, error: NSError) {
        print("🔧 [macOS] Attempting migration error recovery...")
        
        guard let storeURL = storeDescription.url else {
            print("❌ [macOS] Cannot recover: no store URL")
            return
        }
        
        // Strategy 1: Try to backup and recreate the store
        do {
            let fileManager = FileManager.default
            let backupURL = storeURL.appendingPathExtension("backup-\(Date().timeIntervalSince1970)")
            
            // Backup the existing store
            if fileManager.fileExists(atPath: storeURL.path) {
                try fileManager.copyItem(at: storeURL, to: backupURL)
                print("📦 [macOS] Backed up store to: \(backupURL.path)")
                
                // Remove the problematic store files
                try fileManager.removeItem(at: storeURL)
                
                let walURL = storeURL.appendingPathExtension("sqlite-wal")
                let shmURL = storeURL.appendingPathExtension("sqlite-shm")
                
                if fileManager.fileExists(atPath: walURL.path) {
                    try fileManager.removeItem(at: walURL)
                }
                if fileManager.fileExists(atPath: shmURL.path) {
                    try fileManager.removeItem(at: shmURL)
                }
                
                print("🗑️ [macOS] Removed problematic store files")
            }
            
            // Try to load the store again with a fresh start
            print("🔄 [macOS] Attempting to create fresh store...")
            container.loadPersistentStores { (_, retryError) in
                if let retryError = retryError {
                    print("❌ [macOS] Failed to create fresh store: \(retryError)")
                    fatalError("Could not recover from Core Data migration error: \(retryError)")
                } else {
                    print("✅ [macOS] Successfully created fresh Core Data store")
                    print("📝 [macOS] Previous data backed up to: \(backupURL.path)")
                    print("💡 [macOS] You can restore data manually if needed")
                }
            }
            
        } catch {
            print("❌ [macOS] Migration recovery failed: \(error)")
            fatalError("Could not recover from Core Data migration error: \(error)")
        }
    }
}
