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
    @State private var isHovered = false
    @State private var showingFullContent = false
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onPin: () -> Void
    
    private var contentPreview: String {
        let content = item.content ?? ""
        if content.count > 150 {
            return String(content.prefix(150)) + "..."
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
            // Header with app info and actions
            HStack {
                // App icon and info
                HStack(spacing: 8) {
                    if let iconData = item.sourceAppIcon,
                       let nsImage = NSImage(data: iconData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Image(systemName: "app.fill")
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.sourceAppName ?? "Unknown App")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text(timeAgo)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Content type badge
                ContentTypeBadge(contentType: ContentType(rawValue: item.contentType ?? "text") ?? .text)
                
                // Pin indicator
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                if let content = item.content {
                    if item.contentType == "url" {
                        URLContentView(url: content)
                    } else if item.contentType == "image" {
                        ImageContentView(placeholder: content)
                    } else {
                        TextContentView(text: showingFullContent ? content : contentPreview)
                    }
                }
                
                // Show more/less button for long content
                if (item.content?.count ?? 0) > 150 {
                    Button(action: { showingFullContent.toggle() }) {
                        Text(showingFullContent ? "Show less" : "Show more")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            
            // Action buttons (shown on hover)
            if isHovered {
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
                .padding(.bottom, 10)
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
        .shadow(color: .black.opacity(isHovered ? 0.1 : 0.05), radius: isHovered ? 8 : 4)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("Copy to Clipboard") { onCopy() }
            Button(item.isPinned ? "Unpin" : "Pin") { onPin() }
            Divider()
            Button("Delete") { onDelete() }
        }
    }
}

// MARK: - Content Type Badge

struct ContentTypeBadge: View {
    let contentType: ContentType
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: contentType.systemImage)
                .font(.caption2)
            Text(contentType.displayName)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(badgeColor.opacity(0.2))
        )
        .foregroundColor(badgeColor)
    }
    
    private var badgeColor: Color {
        switch contentType {
        case .text:
            return .blue
        case .url:
            return .green
        case .image:
            return .purple
        }
    }
}

// MARK: - Content Views

struct TextContentView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.body)
            .lineLimit(nil)
            .textSelection(.enabled)
            .padding(.vertical, 4)
    }
}

struct URLContentView: View {
    let url: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(url)
                .font(.body)
                .foregroundColor(.accentColor)
                .textSelection(.enabled)
            
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
        .padding(.vertical, 4)
        .onTapGesture {
            if let nsUrl = URL(string: url) {
                NSWorkspace.shared.open(nsUrl)
            }
        }
    }
}

struct ImageContentView: View {
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
            }
        }
        .padding(.vertical, 8)
    }
} 