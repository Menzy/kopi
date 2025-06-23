//
//  ClipboardCorrelator.swift
//  kopi
//
//  Created by AI Assistant on 19/06/2025.
//

import Foundation
import CoreData

struct CorrelationResult {
    let isUniversalClipboard: Bool
    let confidence: Double // 0.0 to 1.0
    let matchingItem: ClipboardItem?
    let suggestedCanonicalID: UUID?
    let matchReason: String
}

struct ClipboardEvent {
    let content: String
    let contentType: ContentType
    let timestamp: Date
    let contentHash: String
    let deviceID: String
    
    init(content: String, contentType: ContentType, deviceID: String) {
        self.content = content
        self.contentType = contentType
        self.timestamp = Date()
        self.deviceID = deviceID
        self.contentHash = ClipboardCorrelator.generateContentHash(content)
    }
}

class ClipboardCorrelator: ObservableObject {
    static let shared = ClipboardCorrelator()
    
    private let deviceManager = DeviceManager.shared
    private let persistenceController = PersistenceController.shared
    
    // Timing windows for correlation
    private let universalClipboardWindow: TimeInterval = 15.0 // 15 seconds
    private let contentSimilarityThreshold: Double = 0.85
    private let minimumContentLength: Int = 3
    
    // Track recent clipboard events
    private var recentEvents: [ClipboardEvent] = []
    private let maxRecentEvents = 50
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Correlate incoming clipboard content with recent activity to determine source
    func correlateWithUniversalClipboard(content: String, contentType: ContentType) -> CorrelationResult {
        let event = ClipboardEvent(content: content, contentType: contentType, deviceID: deviceManager.getDeviceID())
        
        // Clean up old events first
        cleanupOldEvents()
        
        // Add this event to recent events
        recentEvents.append(event)
        if recentEvents.count > maxRecentEvents {
            recentEvents.removeFirst()
        }
        
        // Check for Universal Clipboard correlation
        let result = analyzeForUniversalClipboard(event: event)
        
        print("🔍 [Correlator] Content correlation:")
        print("   📄 Content: \(content.prefix(50))")
        print("   🎯 Confidence: \(String(format: "%.2f", result.confidence))")
        print("   📡 Universal Clipboard: \(result.isUniversalClipboard)")
        print("   💭 Reason: \(result.matchReason)")
        
        return result
    }
    
    /// Find canonical ID for content that might already exist from another device
    func findCanonicalID(for content: String, within timeWindow: TimeInterval = 30.0) -> UUID? {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        
        // Look for items created within the time window
        let cutoffDate = Date().addingTimeInterval(-timeWindow)
        fetchRequest.predicate = NSPredicate(format: "content == %@ AND timestamp >= %@", content, cutoffDate as NSDate)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.timestamp, ascending: false)]
        fetchRequest.fetchLimit = 1
        
        do {
            let items = try context.fetch(fetchRequest)
            if let mostRecent = items.first {
                print("🔗 [Correlator] Found canonical ID: \(mostRecent.canonicalID?.uuidString ?? "none")")
                return mostRecent.canonicalID
            }
        } catch {
            print("❌ [Correlator] Error finding canonical ID: \(error)")
        }
        
        return nil
    }
    
    /// Check if content is similar enough to be considered the same
    func isSimilarContent(_ content1: String, _ content2: String) -> Bool {
        // Exact match
        if content1 == content2 {
            return true
        }
        
        // Skip similarity check for very short content
        guard content1.count >= minimumContentLength && content2.count >= minimumContentLength else {
            return false
        }
        
        // Calculate similarity
        let similarity = calculateStringSimilarity(content1, content2)
        return similarity >= contentSimilarityThreshold
    }
    
    /// Register a clipboard action that this device initiated
    func registerLocalClipboardAction(content: String, contentType: ContentType) {
        let event = ClipboardEvent(content: content, contentType: contentType, deviceID: deviceManager.getDeviceID())
        recentEvents.append(event)
        
        print("📝 [Correlator] Registered local action: \(content.prefix(30))")
        
        // Keep recent events manageable
        if recentEvents.count > maxRecentEvents {
            recentEvents.removeFirst()
        }
    }
    
    /// Get recent events for debugging
    func getRecentEvents() -> [ClipboardEvent] {
        return Array(recentEvents.suffix(10)) // Last 10 events
    }
    
    // MARK: - Private Methods
    
    private func analyzeForUniversalClipboard(event: ClipboardEvent) -> CorrelationResult {
        // Check if we have any recent events from THIS device that match
        let recentLocalEvents = recentEvents.filter { otherEvent in
            otherEvent.deviceID == deviceManager.getDeviceID() &&
            event.timestamp.timeIntervalSince(otherEvent.timestamp) < universalClipboardWindow
        }
        
        // Look for exact content matches
        if let matchingEvent = recentLocalEvents.first(where: { $0.content == event.content }) {
            let timeDiff = event.timestamp.timeIntervalSince(matchingEvent.timestamp)
            
            if timeDiff > 1.0 { // Minimum 1 second to avoid immediate duplicates
                return CorrelationResult(
                    isUniversalClipboard: true,
                    confidence: 0.95,
                    matchingItem: nil,
                    suggestedCanonicalID: findCanonicalID(for: event.content),
                    matchReason: "Exact content match from \(String(format: "%.1f", timeDiff))s ago"
                )
            }
        }
        
        // Look for similar content matches
        for recentEvent in recentLocalEvents {
            if isSimilarContent(event.content, recentEvent.content) {
                let timeDiff = event.timestamp.timeIntervalSince(recentEvent.timestamp)
                
                if timeDiff > 1.0 {
                    let similarity = calculateStringSimilarity(event.content, recentEvent.content)
                    return CorrelationResult(
                        isUniversalClipboard: true,
                        confidence: similarity,
                        matchingItem: nil,
                        suggestedCanonicalID: findCanonicalID(for: recentEvent.content),
                        matchReason: "Similar content match (\(String(format: "%.0f", similarity * 100))% similar)"
                    )
                }
            }
        }
        
        // Check CloudKit items for recent matches (Universal Clipboard from other devices)
        if let cloudKitMatch = checkCloudKitForRecentMatch(event: event) {
            return cloudKitMatch
        }
        
        // No correlation found - likely local action
        return CorrelationResult(
            isUniversalClipboard: false,
            confidence: 0.1,
            matchingItem: nil,
            suggestedCanonicalID: nil,
            matchReason: "No recent correlation found - likely local action"
        )
    }
    
    private func checkCloudKitForRecentMatch(event: ClipboardEvent) -> CorrelationResult? {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        
        // Look for items from OTHER devices within the Universal Clipboard window
        let cutoffDate = Date().addingTimeInterval(-universalClipboardWindow)
        fetchRequest.predicate = NSPredicate(
            format: "timestamp >= %@ AND initiatingDevice != %@ AND initiatingDevice != nil",
            cutoffDate as NSDate,
            deviceManager.getDeviceID()
        )
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.timestamp, ascending: false)]
        fetchRequest.fetchLimit = 10
        
        do {
            let recentItems = try context.fetch(fetchRequest)
            
            for item in recentItems {
                guard let itemContent = item.content else { continue }
                
                if isSimilarContent(event.content, itemContent) {
                    let timeDiff = event.timestamp.timeIntervalSince(item.timestamp ?? Date.distantPast)
                    let similarity = calculateStringSimilarity(event.content, itemContent)
                    
                    return CorrelationResult(
                        isUniversalClipboard: true,
                        confidence: similarity,
                        matchingItem: item,
                        suggestedCanonicalID: item.canonicalID,
                        matchReason: "CloudKit match from \(item.initiatingDevice ?? "unknown device") (\(String(format: "%.1f", timeDiff))s ago)"
                    )
                }
            }
        } catch {
            print("❌ [Correlator] Error checking CloudKit: \(error)")
        }
        
        return nil
    }
    
    private func cleanupOldEvents() {
        let cutoffDate = Date().addingTimeInterval(-universalClipboardWindow * 2) // Keep 2x the window
        recentEvents.removeAll { $0.timestamp < cutoffDate }
    }
    
    private func calculateStringSimilarity(_ str1: String, _ str2: String) -> Double {
        // Simple implementation using edit distance
        let distance = levenshteinDistance(str1, str2)
        let maxLength = max(str1.count, str2.count)
        
        guard maxLength > 0 else { return 1.0 }
        
        return 1.0 - (Double(distance) / Double(maxLength))
    }
    
    private func levenshteinDistance(_ str1: String, _ str2: String) -> Int {
        let m = str1.count
        let n = str2.count
        
        if m == 0 { return n }
        if n == 0 { return m }
        
        let str1Array = Array(str1)
        let str2Array = Array(str2)
        
        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m {
            matrix[i][0] = i
        }
        
        for j in 0...n {
            matrix[0][j] = j
        }
        
        for i in 1...m {
            for j in 1...n {
                let cost = str1Array[i-1] == str2Array[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }
        
        return matrix[m][n]
    }
    
    static func generateContentHash(_ content: String) -> String {
        var hasher = Hasher()
        hasher.combine(content)
        return String(hasher.finalize())
    }
} 