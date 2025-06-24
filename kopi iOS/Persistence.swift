//
//  Persistence.swift
//  kopi ios
//
//  Created by Wan Menzy on 20/06/2025.
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
            ("Hello from iOS!", ContentType.text),
            ("https://www.apple.com", ContentType.url),
            ("iOS clipboard text for testing the preview", ContentType.text)
        ]
        
        for (content, type) in sampleItems {
            let item = ClipboardItem(context: viewContext)
            item.id = UUID()
            item.content = content
            item.contentType = type.rawValue
            item.createdAt = Date().addingTimeInterval(-Double.random(in: 0...3600))
            item.lastModified = Date()
            item.createdOnDevice = "iOS"
            item.markedAsDeleted = false
            item.contentHash = ContentHashingUtility.generateContentHash(from: content)
            item.iCloudSyncStatus = SyncStatus.local.rawValue
            item.sourceAppName = "Preview"
        }
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "kopi")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Configure for local-only Core Data storage
            guard let description = container.persistentStoreDescriptions.first else {
                fatalError("Failed to retrieve a persistent store description.")
            }
            
            // Enable persistent history tracking for manual CloudKit sync
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            
            print("🔧 [iOS] Configured Core Data for local-only storage (manual CloudKit sync)")
        }
        
        // Load persistent stores with simple error handling
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                print("❌ [iOS] Core Data error: \(error.localizedDescription)")
                fatalError("Unresolved Core Data error: \(error), \(error.userInfo)")
            } else {
                print("✅ [iOS] Core Data store loaded successfully")
                if let storeURL = storeDescription.url {
                    print("📊 [iOS] Store location: \(storeURL.path)")
                }
            }
        }
        
        // Configure the view context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Enable persistent history tracking
        do {
            try container.viewContext.setQueryGenerationFrom(.current)
        } catch {
            print("Failed to pin viewContext to the current generation: \(error)")
        }
        
        // Add Core Data change monitoring for manual CloudKit sync
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { notification in
            print("📡 [iOS] Core Data remote change notification received")
        }
    }
}
