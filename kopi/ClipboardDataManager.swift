//
//  ClipboardDataManager.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import Foundation
import CoreData
import CloudKit
import AppKit

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
    
    func deleteClipboardItems(_ items: [ClipboardItem]) {
        for item in items {
            viewContext.delete(item)
        }
        saveContext()
    }
    

    
    func markAsSensitive(_ item: ClipboardItem) {
        item.isSensitive = true
        saveContext()
    }
    
    func updateClipboardItem(_ item: ClipboardItem, content: String) {
        item.content = content
        item.contentPreview = createPreview(from: content, type: ContentType(rawValue: item.contentType ?? "text") ?? .text)
        item.fileSize = Int64(content.data(using: .utf8)?.count ?? 0)
        saveContext()
    }
    
    // MARK: - Enhanced Query Methods
    
    func getRecentItems(limit: Int = 50) -> [ClipboardItem] {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.predicate = NSPredicate(format: "isTransient == NO")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.timestamp, ascending: false)]
        request.fetchLimit = limit
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch recent items: \(error)")
            return []
        }
    }
    
    func getAvailableApps() -> [String] {
        let request: NSFetchRequest<NSFetchRequestResult> = ClipboardItem.fetchRequest()
        request.predicate = NSPredicate(format: "isTransient == NO AND sourceAppName != nil")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["sourceAppName"]
        request.returnsDistinctResults = true
        
        do {
            let results = try viewContext.fetch(request) as? [[String: Any]] ?? []
            return results.compactMap { $0["sourceAppName"] as? String }.sorted()
        } catch {
            print("❌ Failed to fetch available apps: \(error)")
            return []
        }
    }
    
    func searchItems(
        searchText: String? = nil,
        contentType: ContentType? = nil,
        sourceApp: String? = nil,

    ) -> [ClipboardItem] {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        
        var predicates: [NSPredicate] = [NSPredicate(format: "isTransient == NO")]
        
        // Search text
        if let searchText = searchText, !searchText.isEmpty {
            predicates.append(NSPredicate(format: "content CONTAINS[cd] %@", searchText))
        }
        
        // Content type filter
        if let contentType = contentType {
            predicates.append(NSPredicate(format: "contentType == %@", contentType.rawValue))
        }
        
        // Source app filter
        if let sourceApp = sourceApp {
            predicates.append(NSPredicate(format: "sourceAppName == %@", sourceApp))
        }
        

        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        // Always sort by newest first
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.timestamp, ascending: false)]
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("❌ Failed to search items: \(error)")
            return []
        }
    }
    
    func copyToClipboard(_ item: ClipboardItem) {
        guard let content = item.content else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        // Set content based on type
        switch ContentType(rawValue: item.contentType ?? "text") ?? .text {
        case .text, .url:
            pasteboard.setString(content, forType: .string)
        case .image:
            // Handle base64 encoded image data
            if let imageData = Data(base64Encoded: content) {
                pasteboard.setData(imageData, forType: .tiff)
            } else {
                // Fallback to string if not base64
                pasteboard.setString(content, forType: .string)
            }
        }
        
        print("📋 Copied to clipboard: \(content.prefix(50))...")
    }
    
    // MARK: - App Statistics
    
    func getAppStatistics() -> [AppInfo] {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.predicate = NSPredicate(format: "isTransient == NO")
        
        do {
            let items = try viewContext.fetch(request)
            
            // Group by bundle ID and count items
            let groupedItems = Dictionary(grouping: items) { item in
                item.sourceApp ?? "unknown"
            }
            
            let appInfos = groupedItems.compactMap { (bundleID, items) -> AppInfo? in
                guard let firstItem = items.first else { return nil }
                
                return AppInfo(
                    bundleID: bundleID,
                    name: firstItem.sourceAppName ?? "Unknown App",
                    iconData: firstItem.sourceAppIcon,
                    itemCount: items.count
                )
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } // Sort alphabetically by name
            
            return appInfos
        } catch {
            print("Failed to fetch app statistics: \(error)")
            return []
        }
    }
    
    func getTotalItemCount() -> Int {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.predicate = NSPredicate(format: "isTransient == NO")
        
        do {
            return try viewContext.count(for: request)
        } catch {
            print("Failed to get total item count: \(error)")
            return 0
        }
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