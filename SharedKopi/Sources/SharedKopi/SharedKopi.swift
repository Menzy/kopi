//
//  SharedKopi.swift
//  SharedKopi
//
//  Created by Wan Menzy on 25/06/2025.
//

import Foundation
import CoreData

public class SharedKopiManager {
    public static let shared = SharedKopiManager()
    
    private init() {}
    
    // MARK: - Core Data Stack
    
    public lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "kopi")
        
        // Configure store URL to use app group
        if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.menzy.kopi") {
            let storeURL = appGroupURL.appendingPathComponent("kopi.sqlite")
            
            let description = NSPersistentStoreDescription(url: storeURL)
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            
            container.persistentStoreDescriptions = [description]
        }
        
        container.loadPersistentStores { _, error in
            if let error = error {
                print("❌ [SharedKopi] Core Data error: \(error)")
            } else {
                print("✅ [SharedKopi] Core Data loaded successfully")
            }
        }
        
        return container
    }()
    
    public var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    // MARK: - Clipboard Operations
    
    public func fetchRecentClipboardItems(limit: Int = 20) -> [ClipboardItem] {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.predicate = NSPredicate(format: "markedAsDeleted == NO")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)]
        request.fetchLimit = limit
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("❌ [SharedKopi] Failed to fetch clipboard items: \(error)")
            return []
        }
    }
    
    public func searchClipboardItems(_ searchText: String, limit: Int = 20) -> [ClipboardItem] {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        
        var predicates: [NSPredicate] = [NSPredicate(format: "markedAsDeleted == NO")]
        
        if !searchText.isEmpty {
            predicates.append(NSPredicate(format: "content CONTAINS[cd] %@", searchText))
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)]
        request.fetchLimit = limit
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("❌ [SharedKopi] Search failed: \(error)")
            return []
        }
    }
    
    public func saveContext() {
        if viewContext.hasChanges {
            do {
                try viewContext.save()
            } catch {
                print("❌ [SharedKopi] Failed to save context: \(error)")
            }
        }
    }
}

// MARK: - ContentType for Shared Use

public enum SharedContentType: String, CaseIterable {
    case text = "text"
    case image = "image"
    case url = "url"
    case file = "file"
    
    public var displayName: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .url: return "Link"
        case .file: return "File"
        }
    }
}

// MARK: - Utility Functions

public class SharedUtilities {
    public static func formatTimeAgo(_ date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 {
            return "now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours)h"
        } else {
            let days = Int(timeInterval / 86400)
            return "\(days)d"
        }
    }
    
    public static func truncateText(_ text: String, maxLength: Int = 60) -> String {
        if text.count <= maxLength {
            return text
        }
        return String(text.prefix(maxLength)) + "..."
    }
} 