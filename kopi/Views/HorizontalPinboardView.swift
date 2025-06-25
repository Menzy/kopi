//
//  HorizontalPinboardView.swift
//  kopi
//
//  Created by Wan Menzy on 25/01/2025.
//

import SwiftUI

struct HorizontalPinboardView: View {
    let onDismiss: () -> Void
    
    @StateObject private var dataManager = ClipboardDataManager.shared
    @State private var clipboardItems: [ClipboardItem] = []
    @State private var hoveredItem: NSManagedObjectID?
    
    private let itemHeight: CGFloat = 140  // Further increased height
    private let itemWidth: CGFloat = 160   // Increased width to match
    private let spacing: CGFloat = 20      // More spacing
    
    var body: some View {
        VStack(spacing: 0) {
            // Horizontal scrollable content
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(clipboardItems.prefix(20), id: \.objectID) { item in
                        HorizontalClipboardCard(
                            item: item,
                            width: itemWidth,
                            height: itemHeight,
                            isHovered: hoveredItem == item.objectID,
                            onCopy: {
                                dataManager.copyToClipboard(item)
                                onDismiss() // Auto-dismiss after copying
                            },
                            onDelete: {
                                dataManager.deleteClipboardItem(item)
                                refreshData()
                            }
                        )
                        .onHover { isHovering in
                            hoveredItem = isHovering ? item.objectID : nil
                        }
                    }
                }
                .padding(.horizontal, 24)  // More horizontal padding
                .padding(.vertical, 20)    // More vertical padding to center items
            }
            .frame(height: itemHeight + 40) // Adjust for increased padding
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        )
        .padding(12)  // Slightly more padding around the entire component
        .onAppear {
            refreshData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardDidChange)) { _ in
            refreshData()
        }
    }
    
    private func refreshData() {
        clipboardItems = dataManager.getRecentItems(limit: 20)
    }
}

struct HorizontalClipboardCard: View {
    let item: ClipboardItem
    let width: CGFloat
    let height: CGFloat
    let isHovered: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    
    private let maxTextLines = 2
    private let maxTextLength = 50
    
    var body: some View {
        VStack(spacing: 6) {
            // Content preview
            VStack(spacing: 4) {
                // App icon and content type indicator
                HStack(spacing: 6) {
                    // App icon
                    if let iconData = item.sourceAppIcon,
                       let nsImage = NSImage(data: iconData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Image(systemName: "app.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 16)
                    }
                    
                    Spacer()
                    
                    // Content type icon
                    contentTypeIcon
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Main content
                contentPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: width, height: height - 30) // Reserve space for timestamp with more room
            
            // Timestamp
            if let timestamp = item.createdAt {
                Text(timeAgoString(from: timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)  // Increased padding inside cards
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isHovered ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                )
        )
        .onTapGesture {
            onCopy()
        }
        .onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .contextMenu {
            Button("Copy", action: onCopy)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
    
    @ViewBuilder
    private var contentTypeIcon: some View {
        let contentType = ContentType(rawValue: item.contentType ?? "text") ?? .text
        
        switch contentType {
        case .text:
            Image(systemName: "textformat")
        case .url:
            Image(systemName: "link")
        case .image:
            Image(systemName: "photo")
        case .file:
            Image(systemName: "doc")
        }
    }
    
    @ViewBuilder
    private var contentPreview: some View {
        if let content = item.content {
            let contentType = ContentType(rawValue: item.contentType ?? "text") ?? .text
            
            switch contentType {
            case .text:
                let displayText = String(content.prefix(maxTextLength))
                Text(displayText + (content.count > maxTextLength ? "..." : ""))
                    .font(.caption)
                    .lineLimit(maxTextLines)
                    .multilineTextAlignment(.leading)
                
            case .url:
                VStack(alignment: .leading, spacing: 2) {
                    Image(systemName: "link")
                        .font(.title3)
                        .foregroundColor(.blue)
                    
                    let displayURL = String(content.prefix(maxTextLength))
                    Text(displayURL + (content.count > maxTextLength ? "..." : ""))
                        .font(.caption2)
                        .lineLimit(2)
                        .foregroundColor(.secondary)
                }
                
            case .image:
                if let imageData = Data(base64Encoded: content),
                   let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: width - 16, maxHeight: height - 40)
                        .clipped()
                        .cornerRadius(4)
                } else {
                    VStack {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Image")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
            case .file:
                VStack {
                    Image(systemName: "doc.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    Text("File")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        } else {
            VStack {
                Image(systemName: "questionmark.circle")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("No Content")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Helper Functions

private func timeAgoString(from date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.dateTimeStyle = .named
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
} 