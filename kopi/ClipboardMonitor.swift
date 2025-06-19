//
//  ClipboardMonitor.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import Foundation
import AppKit
import Combine

class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()
    
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = 0
    private var monitoringTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    @Published var isMonitoring: Bool = false
    @Published var lastClipboardContent: String = ""
    
    private let dataManager = ClipboardDataManager.shared
    private let sourceAppDetector = SourceAppDetector.shared
    private let privacyFilter = PrivacyFilter.shared
    
    private init() {
        lastChangeCount = pasteboard.changeCount
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        print("🔍 Starting clipboard monitoring...")
        isMonitoring = true
        lastChangeCount = pasteboard.changeCount
        
        // Start timer-based monitoring (polling every 0.5 seconds)
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboardChanges()
        }
        
        print("✅ Clipboard monitoring started")
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        print("⏹️ Stopping clipboard monitoring...")
        isMonitoring = false
        
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        print("✅ Clipboard monitoring stopped")
    }
    
    // MARK: - Private Methods
    
    private func checkClipboardChanges() {
        let currentChangeCount = pasteboard.changeCount
        
        // Check if clipboard content has changed
        guard currentChangeCount != lastChangeCount else { return }
        
        lastChangeCount = currentChangeCount
        handleClipboardChange()
    }
    
    private func handleClipboardChange() {
        // Get clipboard content
        guard let clipboardContent = getClipboardContent() else {
            print("⚠️ No valid clipboard content found")
            return
        }
        
        // Detect source application first
        let sourceAppInfo = sourceAppDetector.detectCurrentApp()
        
        // Check for privacy restrictions
        let privacyCheck = privacyFilter.shouldExcludeContent(
            clipboardContent.content,
            sourceApp: sourceAppInfo.bundleID
        )
        
        if privacyCheck.shouldExclude {
            print("🔒 Clipboard content excluded: \(privacyCheck.reason ?? "Privacy filter")")
            return
        }
        
        // Save to data store
        saveClipboardItem(
            content: clipboardContent.content,
            type: clipboardContent.type,
            sourceApp: sourceAppInfo.bundleID,
            sourceAppName: sourceAppInfo.name,
            sourceAppIcon: sourceAppInfo.iconData
        )
        
        // Update published property
        lastClipboardContent = clipboardContent.content
        
        print("📋 Clipboard content saved: \(clipboardContent.content.prefix(50))...")
    }
    
    private func getClipboardContent() -> ClipboardContent? {
        // Check for different content types in order of preference
        
        // 1. Check for URLs first
        if let url = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .fileURL) {
            return ClipboardContent(content: url, type: .url)
        }
        
        // 2. Check for regular text
        if let string = pasteboard.string(forType: .string) {
            // Determine if it's a URL or regular text
            if isValidURL(string) {
                return ClipboardContent(content: string, type: .url)
            } else {
                return ClipboardContent(content: string, type: .text)
            }
        }
        
        // 3. Check for images (basic support)
        if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .jpeg) {
            // For now, we'll store a placeholder for images
            // In a future phase, we can add proper image handling
            let imagePlaceholder = "[Image: \(imageData.count) bytes]"
            return ClipboardContent(content: imagePlaceholder, type: .image)
        }
        
        return nil
    }
    
    private func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return url.scheme != nil && (url.scheme == "http" || url.scheme == "https" || url.scheme == "file")
    }
    

    
    private func saveClipboardItem(content: String, type: ContentType, sourceApp: String?, sourceAppName: String?, sourceAppIcon: Data?) {
        _ = dataManager.createClipboardItem(
            content: content,
            contentType: type,
            sourceApp: sourceApp,
            sourceAppName: sourceAppName,
            sourceAppIcon: sourceAppIcon
        )
    }
}

// MARK: - Supporting Types

struct ClipboardContent {
    let content: String
    let type: ContentType
}

extension NSPasteboard.PasteboardType {
    static let jpeg = NSPasteboard.PasteboardType("public.jpeg")
} 