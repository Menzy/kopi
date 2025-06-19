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
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content preview
            ScrollView {
                contentPreview
                    .padding(20)
            }
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
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 600, height: 500)
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
            return "URL"
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
                if isEditing {
                    TextEditor(text: $editedContent)
                        .font(.system(.body, design: .default))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 300)
                } else {
                    Text(content)
                        .font(.system(.body, design: .default))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .url:
                if isEditing {
                    TextEditor(text: $editedContent)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 100)
                } else {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.blue)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .image:
                if let imageData = Data(base64Encoded: content),
                   let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 350)
                } else {
                    Text("Unable to load image")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            Text("No content available")
                .foregroundColor(.secondary)
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
                // Handle image data copying
                if let imageData = Data(base64Encoded: content),
                   let nsImage = NSImage(data: imageData) {
                    pasteboard.setData(nsImage.tiffRepresentation, forType: .tiff)
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



 