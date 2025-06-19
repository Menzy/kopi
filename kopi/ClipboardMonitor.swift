//
//  ClipboardMonitor.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import Foundation
import AppKit
import Combine
import Cocoa
import CoreData
import UniformTypeIdentifiers

class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()
    
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = 0
    private var lastContentHash: Int = 0
    private var monitoringTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    @Published var isMonitoring: Bool = false
    @Published var lastClipboardContent: String = ""
    @Published var clipboardDidChange: Bool = false
    
    private let dataManager = ClipboardDataManager.shared
    private let sourceAppDetector = SourceAppDetector.shared
    private let privacyFilter = PrivacyFilter.shared
    
    private init() {
        lastChangeCount = pasteboard.changeCount
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        lastChangeCount = pasteboard.changeCount
        lastContentHash = getClipboardContentHash()
        
        // Start high-frequency timer-based monitoring (polling every 0.05 seconds for ultra-fast response)
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkClipboardChanges()
        }
        
        // Set timer to high priority for better responsiveness
        if let timer = monitoringTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
        
        // Also listen for app activation events to check immediately when switching apps
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Immediate check when app becomes active
            self?.checkClipboardChanges()
        }
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)
    }
    
    func forceCheck() {
        // Manual method to force an immediate clipboard check
        checkClipboardChanges()
    }
    
    // MARK: - Private Methods
    
    private func checkClipboardChanges() {
        let currentChangeCount = pasteboard.changeCount
        
        // Quick exit if change count hasn't changed
        guard currentChangeCount != lastChangeCount else { return }
        
        // Get content hash for additional validation
        let currentContentHash = getClipboardContentHash()
        
        // Double-check to avoid processing the same content multiple times
        guard currentContentHash != lastContentHash else {
            lastChangeCount = currentChangeCount
            return
        }
        
        lastChangeCount = currentChangeCount
        lastContentHash = currentContentHash
        handleClipboardChange()
    }
    
    private func getClipboardContentHash() -> Int {
        // Quick hash of clipboard content to detect actual changes
        var hasher = Hasher()
        
        // Hash the most common types quickly
        if let string = pasteboard.string(forType: .string) {
            hasher.combine(string)
        }
        if let url = pasteboard.string(forType: .URL) {
            hasher.combine(url)
        }
        if let data = pasteboard.data(forType: .png) {
            hasher.combine(data.count) // Use data size for images to avoid processing large data
        }
        
        return hasher.finalize()
    }
    
    private func handleClipboardChange() {
        // Process clipboard changes on a background queue to avoid blocking the timer
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Get clipboard content
            guard let clipboardContent = self.checkClipboardContent() else {
                return
            }
            
            // Detect source application first
            let sourceAppInfo = self.sourceAppDetector.detectCurrentApp()
            
            // Check for privacy restrictions
            let privacyCheck = self.privacyFilter.shouldExcludeContent(
                clipboardContent.content,
                contentType: clipboardContent.type,
                sourceApp: sourceAppInfo.bundleID
            )
            
            if privacyCheck.shouldExclude {
                return
            }
            
            // Save to data store
            self.saveClipboardItem(
                content: clipboardContent.content,
                type: clipboardContent.type,
                sourceApp: sourceAppInfo.bundleID,
                sourceAppName: sourceAppInfo.name,
                sourceAppIcon: sourceAppInfo.iconData
            )
            
            // Update published properties on main queue
            DispatchQueue.main.async {
                self.lastClipboardContent = clipboardContent.content
                self.clipboardDidChange.toggle() // Trigger UI refresh
            }
        }
    }
    
    private func checkClipboardContent() -> ClipboardContent? {
        let pasteboard = NSPasteboard.general
        
        // 1. First priority: Get original image data in native format
        let imageTypes = [
            NSPasteboard.PasteboardType.png,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.jpg"), 
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("public.heif"),
            NSPasteboard.PasteboardType("public.gif"),
            NSPasteboard.PasteboardType("public.bmp"),
            NSPasteboard.PasteboardType("public.webp"),
            NSPasteboard.PasteboardType("public.svg-image")
        ]
        
        // Try to get original image data first
        for imageType in imageTypes {
            if let imageData = pasteboard.data(forType: imageType) {
                // Verify it's valid image data
                if let _ = NSImage(data: imageData) {
                    let base64String = imageData.base64EncodedString()
                    return ClipboardContent(content: base64String, type: .image)
                }
            }
        }
        
        // 2. Check for file URLs that might be images
        if let fileURL = pasteboard.string(forType: .fileURL) {
            if let url = URL(string: fileURL) {
                // Check if it's an image file and try to read it directly
                if isImageFile(fileURL) || hasImageUTI(url) {
                    do {
                        // Read the actual image file from disk
                        let imageData = try Data(contentsOf: url)
                        
                        // Verify it's actually image data by trying to create NSImage
                        if let _ = NSImage(data: imageData) {
                            let base64String = imageData.base64EncodedString()
                            return ClipboardContent(content: base64String, type: .image)
                        }
                    } catch {
                        // Failed to read image file, continue to other content types
                    }
                }
            }
        }
        
        // 3. Check for TIFF data (fallback for other image sources)
        if let tiffData = pasteboard.data(forType: .tiff) {
            // Only accept larger TIFF files to avoid file icons
            if tiffData.count > 100000, let _ = NSImage(data: tiffData) {
                let base64String = tiffData.base64EncodedString()
                return ClipboardContent(content: base64String, type: .image)
            }
        }
        
        // 4. Check for URLs
        if let urlString = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string) {
            if isValidURL(urlString) {
                return ClipboardContent(content: urlString, type: .url)
            }
        }
        
        // 5. Check for text
        if let text = pasteboard.string(forType: .string) {
            if isValidURL(text) {
                return ClipboardContent(content: text, type: .url)
            } else {
                return ClipboardContent(content: text, type: .text)
            }
        }
        
        return nil
    }
    
    // MARK: - Helper Methods
    
    private func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return url.scheme != nil && (url.scheme == "http" || url.scheme == "https")
    }
    
    private func isImageFile(_ path: String) -> Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "heif", "webp", "svg"]
        let pathExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        return imageExtensions.contains(pathExtension)
    }
    
    private func hasImageUTI(_ url: URL) -> Bool {
        guard let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier else {
            return false
        }
        return UTType(uti)?.conforms(to: .image) == true
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