//
//  ClipboardPreviewWindow.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import SwiftUI
import AppKit
import WebKit

struct ClipboardPreviewPopover: View {
    let item: ClipboardItem
    @Binding var isPresented: Bool
    let onSave: (ClipboardItem, String) -> Void
    @State private var isEditing = false
    @State private var editedContent = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with title and edit button
            HStack {
                Text(previewTitle)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Only show edit button for text content
                if ContentType(rawValue: item.contentType ?? "text") == .text {
                    Button(action: {
                        if isEditing {
                            saveChanges()
                        } else {
                            startEditing()
                        }
                    }) {
                        Text(isEditing ? "Save" : "Edit")
                            .font(.system(.caption, weight: .medium))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Divider()
            
            // Content preview (larger version)
            contentPreview
                .frame(maxHeight: 400) // Increased from 200 to 400
            
            Divider()
            
            // Footer with source app and copy button
            HStack {
                // Source app info
                HStack(spacing: 6) {
                    if let iconData = item.sourceAppIcon,
                       let nsImage = NSImage(data: iconData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    
                    Text("From \(item.sourceAppName ?? "Unknown")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Copy button
                Button("Copy") {
                    copyToClipboard()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16) // Increased from 12 to 16
        .frame(width: 480) // Increased from 320 to 480
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            editedContent = item.content ?? ""
        }
    }
    
    private var previewTitle: String {
        let contentType = ContentType(rawValue: item.contentType ?? "text") ?? .text
        switch contentType {
        case .text:
            return "Text Preview"
        case .url:
            return "URL Preview"
        case .image:
            return "Image Preview"
        }
    }
    
    @ViewBuilder
    private var contentPreview: some View {
        if let content = item.content {
            let contentType = ContentType(rawValue: item.contentType ?? "text") ?? .text
            
            switch contentType {
            case .text:
                ScrollView {
                    if isEditing {
                        TextEditor(text: $editedContent)
                            .font(.system(.body, design: .default))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 200, maxHeight: 350)
                    } else {
                        Text(content)
                            .font(.system(.body, design: .default))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                    }
                }
                
            case .url:
                VStack(alignment: .leading, spacing: 8) {
                    // URL display at top
                    Text(content)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.blue)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                    
                    // Link preview (larger version for preview window)
                    LinkPreviewCard(url: content, isCompact: false)
                        .frame(height: 300)
                        .cornerRadius(8)
                }
                
            case .image:
                VStack(alignment: .leading, spacing: 8) {
                    if let imageData = Data(base64Encoded: content) {
                        if let nsImage = NSImage(data: imageData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 440, maxHeight: 300)
                                .cornerRadius(8)
                        } else {
                            HStack {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .foregroundColor(.red)
                                Text("Unable to load image")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                Spacer()
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            .cornerRadius(6)
                        }
                    } else {
                        HStack {
                            Image(systemName: "photo.badge.exclamationmark")
                                .foregroundColor(.red)
                            Text("Invalid image data")
                                .font(.caption)
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                    }
                    
                    // Image info
                    if let imageData = Data(base64Encoded: content) {
                        if let nsImage = NSImage(data: imageData) {
                            let size = nsImage.size
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                                Text("\(Int(size.width)) × \(Int(size.height)) pixels")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                    }
                }
            }
        } else {
            HStack {
                Image(systemName: "doc.badge.exclamationmark")
                    .foregroundColor(.secondary)
                Text("No content available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(6)
        }
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if let content = item.content {
            let contentType = ContentType(rawValue: item.contentType ?? "text") ?? .text
            
            // Notify clipboard monitor before copying to avoid loop
            ClipboardMonitor.shared.notifyAppCopiedToClipboard(content: content)
            
            switch contentType {
            case .text, .url:
                pasteboard.setString(content, forType: .string)
            case .image:
                // Handle image data copying - content is base64 encoded
                if let imageData = Data(base64Encoded: content) {
                    pasteboard.setData(imageData, forType: .tiff)
                }
            }
        }
        
        isPresented = false
    }
    
    private func startEditing() {
        editedContent = item.content ?? ""
        isEditing = true
    }
    
    private func saveChanges() {
        // Save the changes through the callback
        onSave(item, editedContent)
        isEditing = false
    }
}

// MARK: - Legacy ClipboardPreviewWindow (kept for compatibility)

struct ClipboardPreviewWindow: View {
    let item: ClipboardItem
    @Binding var isPresented: Bool
    let onSave: (ClipboardItem, String) -> Void
    
    var body: some View {
        // Redirect to the new popover design
        ClipboardPreviewPopover(
            item: item,
            isPresented: $isPresented,
            onSave: onSave
        )
    }
}

// MARK: - WebView Component (kept for future use)

struct WebView: NSViewRepresentable {
    let url: URL?
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        if let url = url {
            let request = URLRequest(url: url)
            nsView.load(request)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // Handle loading errors gracefully
            let errorHTML = """
            <html>
            <head>
                <style>
                    body {
                        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                        height: 100vh;
                        margin: 0;
                        background-color: #f5f5f5;
                        color: #666;
                    }
                    .error-container {
                        text-align: center;
                        max-width: 400px;
                        padding: 40px;
                    }
                    .error-icon {
                        font-size: 48px;
                        margin-bottom: 16px;
                    }
                    .error-title {
                        font-size: 18px;
                        font-weight: 600;
                        margin-bottom: 8px;
                        color: #333;
                    }
                    .error-message {
                        font-size: 14px;
                        line-height: 1.4;
                    }
                </style>
            </head>
            <body>
                <div class="error-container">
                    <div class="error-icon">🌐</div>
                    <div class="error-title">Unable to load webpage</div>
                    <div class="error-message">The URL could not be loaded. Please check if the URL is valid and accessible.</div>
                </div>
            </body>
            </html>
            """
            webView.loadHTMLString(errorHTML, baseURL: nil)
        }
    }
}





 