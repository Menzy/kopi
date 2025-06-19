//
//  ClipboardDataManager.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import Foundation
import CoreData
import CloudKit

class ClipboardDataManager: ObservableObject {
    static let shared = ClipboardDataManager()
    
    private let persistenceController = PersistenceController.shared
    
    private var viewContext: NSManagedObjectContext {
        persistenceController.container.viewContext
    }
    
    private init() {}
    
    // MARK: - CRUD Operations
    
    func createClipboardItem(
        content: String,
        contentType: ContentType,
        sourceApp: String? = nil,
        sourceAppName: String? = nil,
        sourceAppIcon: Data? = nil
    ) -> ClipboardItem {
        let item = ClipboardItem(context: viewContext)
        item.id = UUID()
        item.content = content
        item.contentType = contentType.rawValue
        item.contentPreview = createPreview(from: content, type: contentType)
        item.timestamp = Date()
        item.deviceOrigin = getDeviceIdentifier()
        item.sourceApp = sourceApp
        item.sourceAppName = sourceAppName
        item.sourceAppIcon = sourceAppIcon
        item.fileSize = Int64(content.data(using: .utf8)?.count ?? 0)
        item.isPinned = false
        item.isTransient = false
        item.isSensitive = false
        
        saveContext()
        return item
    }
    
    func fetchAllClipboardItems() -> [ClipboardItem] {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.timestamp, ascending: false)]
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("Error fetching clipboard items: \(error)")
            return []
        }
    }
    
    func fetchRecentClipboardItems(limit: Int = 50) -> [ClipboardItem] {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.timestamp, ascending: false)]
        request.fetchLimit = limit
        request.predicate = NSPredicate(format: "isTransient == NO")
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("Error fetching recent clipboard items: \(error)")
            return []
        }
    }
    
    func deleteClipboardItem(_ item: ClipboardItem) {
        viewContext.delete(item)
        saveContext()
    }
    
    func togglePin(for item: ClipboardItem) {
        item.isPinned.toggle()
        saveContext()
    }
    
    func markAsSensitive(_ item: ClipboardItem) {
        item.isSensitive = true
        saveContext()
    }
    
    // MARK: - Helper Methods
    
    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }
    
    private func createPreview(from content: String, type: ContentType) -> String {
        let maxLength = 100
        if content.count <= maxLength {
            return content
        }
        return String(content.prefix(maxLength)) + "..."
    }
    
    private func getDeviceIdentifier() -> String {
        #if os(macOS)
        return "macOS"
        #elseif os(iOS)
        return "iOS"
        #else
        return "Unknown"
        #endif
    }
} 