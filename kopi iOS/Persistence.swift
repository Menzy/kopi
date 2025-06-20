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
            item.contentPreview = content.count > 50 ? String(content.prefix(50)) + "..." : content
            item.timestamp = Date().addingTimeInterval(-Double.random(in: 0...3600))
            item.deviceOrigin = "iOS"
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
            // Configure CloudKit - same configuration as macOS
            guard let description = container.persistentStoreDescriptions.first else {
                fatalError("Failed to retrieve a persistent store description.")
            }
            
            // Enable CloudKit sync
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                print("Core Data error: \(error), \(error.userInfo)")
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        
        // Configure the view context - same as macOS
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Enable persistent history tracking
        do {
            try container.viewContext.setQueryGenerationFrom(.current)
        } catch {
            print("Failed to pin viewContext to the current generation: \(error)")
        }
    }
}
