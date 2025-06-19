//
//  ClipboardItemCard.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import SwiftUI
import AppKit



struct ClipboardItemCard: View {
    let item: ClipboardItem
    let isSelected: Bool
    let cardSize: CGFloat
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onPin: () -> Void
    let onSelect: () -> Void
    let onPreview: () -> Void
    
    @State private var showingFullContent = false
    @State private var showingContextMenu = false
    
    private let maxPreviewLength = 100 // Reduced for fixed size
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with app icon and timestamp
            HStack {
                // App icon only
                if let iconData = item.sourceAppIcon,
                   let nsImage = NSImage(data: iconData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: "app.fill")
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                
                Spacer()
                
                // Timestamp
                if let timestamp = item.timestamp {
                    Text(timeAgoString(from: timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Content preview - optimized for square layout
            VStack(alignment: .leading, spacing: 6) {
                if let content = item.content {
                    let contentType = ContentType(rawValue: item.contentType ?? "text") ?? .text
                    
                    switch contentType {
                    case .text:
                        let displayContent = String(content.prefix(maxPreviewLength))
                        
                        Text(displayContent)
                            .font(.system(.caption, design: .default))
                            .foregroundColor(.primary)
                            .lineLimit(3)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.leading)
                        
                    case .url:
                        Text(content)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.blue)
                            .lineLimit(3)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.leading)
                        
                    case .image:
                        // Show image thumbnail if possible
                        if let imageData = Data(base64Encoded: content) {
                            if let nsImage = NSImage(data: imageData) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 120, height: 80)
                                    .clipped()
                                    .cornerRadius(6)
                            } else {
                                HStack {
                                    Image(systemName: "photo.badge.exclamationmark")
                                        .foregroundColor(.red)
                                        .font(.title3)
                                    Text("Image Error")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                    Spacer()
                                }
                            }
                        } else {
                            HStack {
                                Image(systemName: "photo")
                                    .foregroundColor(.secondary)
                                    .font(.title3)
                                Text("Image")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer() // Push bottom content to bottom
            
            // Bottom info and settings
            HStack {
                // Content info (character count, URL, or dimensions)
                if let content = item.content {
                    let contentType = ContentType(rawValue: item.contentType ?? "text") ?? .text
                    
                    switch contentType {
                    case .text:
                        HStack(spacing: 4) {
                            Image(systemName: "textformat")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(content.count) characters")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                    case .url:
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(content)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                    case .image:
                        HStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            // Show actual image dimensions if possible
                            if let imageData = Data(base64Encoded: content) {
                                if let nsImage = NSImage(data: imageData) {
                                    let size = nsImage.size
                                    Text("\(Int(size.width)) × \(Int(size.height))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Image Error")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            } else {
                                Text("Image")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Settings cog (only when selected)
                if isSelected {
                    Button(action: { showingContextMenu = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .transition(.opacity.combined(with: .scale))
                    .popover(isPresented: $showingContextMenu) {
                        VStack(alignment: .leading, spacing: 0) {
                            Button("Preview") {
                                onPreview()
                                showingContextMenu = false
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            
                            Button("Copy") {
                                onCopy()
                                showingContextMenu = false
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            
                            Button(item.isPinned ? "Unpin" : "Pin") {
                                onPin()
                                showingContextMenu = false
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            
                            Divider()
                            
                            Button("Delete") {
                                onDelete()
                                showingContextMenu = false
                            }
                            .buttonStyle(PlainButtonStyle())
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .frame(width: 120)
                    }
                }
            }
        }
        .padding(12) // Reduced padding for fixed size
        .frame(width: cardSize, height: cardSize) // Fixed square size
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSelected ? Color.accentColor : Color.clear,
                            lineWidth: isSelected ? 2 : 0
                        )
                )
        )
        .contentShape(Rectangle()) // Make entire card clickable
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("Preview", action: onPreview)
            Button("Copy", action: onCopy)
            Button(item.isPinned ? "Unpin" : "Pin", action: onPin)
            Divider()
            Button("Delete", action: onDelete)
        }

        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
    
    private func timeAgoString(from date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 {
            return "Just now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m ago"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(timeInterval / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - Content Type Badge

struct ContentTypeBadge: View {
    let contentType: ContentType
    
    var body: some View {
        Text(contentType.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(contentType.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(contentType.color.opacity(0.15))
            )
    }
}

 