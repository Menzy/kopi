//
//  Persistence.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import CoreData
import CloudKit

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
            // Configure CloudKit for fresh start
            guard let description = container.persistentStoreDescriptions.first else {
                fatalError("Failed to retrieve a persistent store description.")
            }
            
            // Enable CloudKit sync
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            
            // Set the correct CloudKit container identifier to match entitlements
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.wanmenzy.kopi-shared")
        }
        
        // Load persistent stores with detailed CloudKit debugging
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                print("❌ [macOS] Core Data error: \(error.localizedDescription)")
                print("❌ [macOS] Error details: \(error.userInfo)")
                fatalError("Unresolved Core Data error: \(error), \(error.userInfo)")
            } else {
                print("✅ [macOS] Core Data store loaded successfully")
                if let storeURL = storeDescription.url {
                    print("📊 [macOS] Store location: \(storeURL.path)")
                }
                
                // Debug CloudKit configuration
                print("📊 [macOS] Store type: \(storeDescription.type)")
                print("📊 [macOS] CloudKit container: \(storeDescription.cloudKitContainerOptions?.containerIdentifier ?? "none")")
                print("📊 [macOS] Store options: \(storeDescription.options)")
                
                // Check if this is a CloudKit store
                if storeDescription.type == NSSQLiteStoreType {
                    if storeDescription.cloudKitContainerOptions != nil {
                        print("✅ [macOS] CloudKit-enabled SQLite store detected")
                    } else {
                        print("⚠️ [macOS] Regular SQLite store (no CloudKit)")
                    }
                } else {
                    print("⚠️ [macOS] Non-SQLite store type: \(storeDescription.type)")
                }
            }
        }
        
        // Check CloudKit account status
        checkCloudKitStatus()
        
        // Configure the view context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Enable persistent history tracking
        do {
            try container.viewContext.setQueryGenerationFrom(.current)
        } catch {
            print("Failed to pin viewContext to the current generation: \(error)")
        }
        
        // Add comprehensive CloudKit sync monitoring
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { notification in
            // CloudKit remote change received (logging disabled for cleaner output)
        }
        
        // Monitor CloudKit import events with detailed server response logging
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { notification in
            if let cloudKitEvent = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event {
                // Only log actual errors, not routine events
                if let error = cloudKitEvent.error {
                    print("❌ [macOS] CloudKit event error: \(error.localizedDescription)")
                    
                    // Check for CloudKit-specific errors
                    if let ckError = error as? CKError {
                        print("❌ [macOS] CKError code: \(ckError.code.rawValue)")
                        print("❌ [macOS] CKError description: \(ckError.localizedDescription)")
                    }
                }
                // Removed verbose success logging
            }
        }
    }
    
    // MARK: - CloudKit Debugging
    private func checkCloudKitStatus() {
        let container = CKContainer(identifier: "iCloud.com.wanmenzy.kopi-shared")
        
        container.accountStatus { status, error in
            DispatchQueue.main.async {
                print("🔍 [macOS] CloudKit Account Status Check:")
                switch status {
                case .available:
                    print("✅ [macOS] CloudKit account available")
                    self.checkCloudKitPermissions(container: container)
                case .noAccount:
                    print("❌ [macOS] No iCloud account signed in")
                case .restricted:
                    print("❌ [macOS] CloudKit access restricted")
                case .couldNotDetermine:
                    print("❌ [macOS] CloudKit status could not be determined")
                case .temporarilyUnavailable:
                    print("⚠️ [macOS] CloudKit temporarily unavailable")
                @unknown default:
                    print("❓ [macOS] Unknown CloudKit status: \(status.rawValue)")
                }
                
                if let error = error {
                    print("❌ [macOS] CloudKit status error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func checkCloudKitPermissions(container: CKContainer) {
        // Skip user discoverability permission as it's not required for Core Data + CloudKit sync
        // and can cause permission errors. Core Data CloudKit sync works without this permission.
        print("🔐 [macOS] CloudKit Permissions:")
        print("✅ [macOS] Using Core Data CloudKit sync (no additional permissions required)")
        
        // Test basic CloudKit connectivity
        self.testCloudKitConnectivity(container: container)
    }
    
    private func testCloudKitConnectivity(container: CKContainer) {
        // Try to fetch user record to test connectivity
        container.fetchUserRecordID { recordID, error in
            DispatchQueue.main.async {
                print("🌐 [macOS] CloudKit Connectivity Test:")
                if let recordID = recordID {
                    print("✅ [macOS] Successfully fetched user record ID: \(recordID.recordName)")
                    print("✅ [macOS] CloudKit connectivity verified")
                } else if let error = error {
                    print("❌ [macOS] Failed to fetch user record: \(error.localizedDescription)")
                    print("❌ [macOS] Error domain: \((error as NSError).domain)")
                    print("❌ [macOS] Error code: \((error as NSError).code)")
                    print("❌ [macOS] Full error info: \((error as NSError).userInfo)")
                    
                    if let ckError = error as? CKError {
                        print("❌ [macOS] CKError code: \(ckError.code.rawValue)")
                        print("❌ [macOS] CKError description: \(ckError.localizedDescription)")
                        
                        // Log server response details
                        if let serverResponseData = ckError.userInfo["ServerResponseBody"] {
                            print("📡 [macOS] Server response body: \(serverResponseData)")
                        }
                        if let requestUUID = ckError.userInfo["RequestUUID"] {
                            print("📡 [macOS] Request UUID: \(requestUUID)")
                        }
                        if let retryAfter = ckError.userInfo[CKErrorRetryAfterKey] {
                            print("📡 [macOS] Retry after: \(retryAfter)")
                        }
                    }
                } else {
                    print("❓ [macOS] Unknown connectivity test result")
                }
            }
        }
    }
}
