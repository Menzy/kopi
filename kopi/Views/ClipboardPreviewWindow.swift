//
//  ClipboardPreviewWindow.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import SwiftUI
import AppKit
import WebKit

struct ClipboardPreviewWindow: View {
    let item: ClipboardItem
    @Binding var isPresented: Bool
    let onSave: (ClipboardItem, String) -> Void
    @FocusState private var isFocused: Bool
    @State private var isEditing = false
    @State private var editedContent = ""
    
    var body: some View {
        VStack(spacing: 0) {
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
                            .font(.system(.body, weight: .medium))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content preview
            contentPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            
            Divider()
            
            // Footer with source app info only
            HStack {
                // Source app info
                HStack(spacing: 8) {
                    if let iconData = item.sourceAppIcon,
                       let nsImage = NSImage(data: iconData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    
                    Text("From \(item.sourceAppName ?? "Unknown App")")
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
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 800, height: 600) // Larger size for better web/image viewing
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear {
            isFocused = true
        }
        .onKeyPress { keyPress in
            if keyPress.key == .escape {
                isPresented = false
                return .handled
            } else if keyPress.key == .space && !isEditing {
                // Only close on space if not in editing mode
                isPresented = false
                return .handled
            }
            return .ignored
        }
        .onAppear {
            editedContent = item.content ?? ""
        }
    }
    
    private var previewTitle: String {
        let contentType = ContentType(rawValue: item.contentType ?? "text") ?? .text
        switch contentType {
        case .text:
            return "Text"
        case .url:
            return "Web Preview"
        case .image:
            return "Image"
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
                            .frame(minHeight: 400)
                    } else {
                        Text(content)
                            .font(.system(.body, design: .default))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                }
                
            case .url:
                VStack(spacing: 0) {
                    // URL display at top
                    HStack {
                        Text(content)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.blue)
                            .textSelection(.enabled)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    
                    // Web view
                    WebView(url: URL(string: content))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
            case .image:
                ScrollView([.horizontal, .vertical]) {
                    if let imageData = Data(base64Encoded: content) {
                        if let nsImage = NSImage(data: imageData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 760, maxHeight: 500) // Leave some padding
                                .padding(20)
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                Text("Unable to create image from data")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("NSImage failed to initialize from the decoded data.")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(40)
                        }
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("Unable to load image")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("The image data may be corrupted or in an unsupported format.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(40)
                    }
                }
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "doc.badge.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No content available")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if let content = item.content {
            let contentType = ContentType(rawValue: item.contentType ?? "text") ?? .text
            
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
    
    private func togglePin() {
        // This would need to be connected to the data manager
        // For now, just close the preview
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
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - WebView Component

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



 