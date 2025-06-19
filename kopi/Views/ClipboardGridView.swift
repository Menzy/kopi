//
//  ClipboardGridView.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import SwiftUI

struct ClipboardGridView: View {
    let items: [ClipboardItem]
    let onCopy: (ClipboardItem) -> Void
    let onDelete: (ClipboardItem) -> Void
    let onPin: (ClipboardItem) -> Void
    
    @State private var hoveredItem: ClipboardItem?
    
    // Responsive grid columns
    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 12)
    ]
    
    var body: some View {
        ScrollView {
            if items.isEmpty {
                EmptyGridStateView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(items, id: \.objectID) { item in
                        ClipboardGridItemCard(
                            item: item,
                            isHovered: hoveredItem?.objectID == item.objectID,
                            onCopy: { onCopy(item) },
                            onDelete: { onDelete(item) },
                            onPin: { onPin(item) }
                        )
                        .onHover { hovering in
                            hoveredItem = hovering ? item : nil
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
}

// MARK: - Grid Item Card

struct ClipboardGridItemCard: View {
    let item: ClipboardItem
    let isHovered: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onPin: () -> Void
    
    @State private var showingFullContent = false
    
    private var contentPreview: String {
        let content = item.content ?? ""
        if content.count > 120 {
            return String(content.prefix(120)) + "..."
        }
        return content
    }
    
    private var timeAgo: String {
        guard let timestamp = item.timestamp else { return "Unknown" }
        
        let now = Date()
        let timeInterval = now.timeIntervalSince(timestamp)
        
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with app info and pin
            HStack(spacing: 8) {
                // App icon and info
                HStack(spacing: 6) {
                    if let iconData = item.sourceAppIcon,
                       let nsImage = NSImage(data: iconData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Image(systemName: "app.fill")
                            .foregroundColor(.secondary)
                            .frame(width: 18, height: 18)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.sourceAppName ?? "Unknown App")
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        
                        Text(timeAgo)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Pin indicator
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
                
                // Content type badge
                ContentTypeBadge(contentType: ContentType(rawValue: item.contentType ?? "text") ?? .text)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            // Content area
            VStack(alignment: .leading, spacing: 8) {
                if let content = item.content {
                    Group {
                        if item.contentType == "url" {
                            URLGridContentView(url: content)
                        } else if item.contentType == "image" {
                            ImageGridContentView(placeholder: content)
                        } else {
                            TextGridContentView(text: showingFullContent ? content : contentPreview)
                        }
                    }
                    .frame(minHeight: 60, maxHeight: showingFullContent ? .infinity : 100)
                }
                
                // Show more/less for long content
                if (item.content?.count ?? 0) > 120 {
                    Button(action: { showingFullContent.toggle() }) {
                        Text(showingFullContent ? "Show less" : "Show more")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            
            // Action buttons (shown on hover)
            if isHovered {
                Divider()
                
                HStack(spacing: 8) {
                    Button(action: onCopy) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(action: onPin) {
                        Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Spacer()
                    
                    Button(action: onDelete) {
                        Label("Delete", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.red)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.1 : 0.05), radius: isHovered ? 6 : 3)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .contextMenu {
            Button("Copy to Clipboard") { onCopy() }
            Button(item.isPinned ? "Unpin" : "Pin") { onPin() }
            Divider()
            Button("Delete") { onDelete() }
        }
    }
}

// MARK: - Grid Content Views

struct TextGridContentView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.body)
            .lineLimit(nil)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct URLGridContentView: View {
    let url: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(url)
                .font(.body)
                .foregroundColor(.accentColor)
                .textSelection(.enabled)
                .lineLimit(3)
            
            if let nsUrl = URL(string: url) {
                HStack {
                    Image(systemName: "link")
                        .font(.caption2)
                    Text(nsUrl.host ?? "Unknown host")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onTapGesture {
            if let nsUrl = URL(string: url) {
                NSWorkspace.shared.open(nsUrl)
            }
        }
    }
}

struct ImageGridContentView: View {
    let placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "photo")
                .font(.title2)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading) {
                Text("Image")
                    .font(.body)
                    .fontWeight(.medium)
                Text(placeholder)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Empty State

struct EmptyGridStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No Clipboard Items")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Copy something to get started!")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Add Test Item") {
                let testContent = "Test clipboard item created at \(Date().formatted())"
                _ = ClipboardDataManager.shared.createClipboardItem(
                    content: testContent,
                    contentType: .text,
                    sourceApp: "com.apple.finder",
                    sourceAppName: "Finder"
                )
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
} 