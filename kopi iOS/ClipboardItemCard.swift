//
//  ClipboardItemCard.swift
//  kopi ios
//
//  Created by Wan Menzy on 20/06/2025.
//

import SwiftUI
import CoreData

struct ClipboardItemCard: View {
    let item: ClipboardItem
    let isLarge: Bool
    let isSelectionMode: Bool
    let isSelected: Bool
    
    // Add cardWidth as a property
    private var cardWidth: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let totalPadding: CGFloat = 32 // 16 on each side
        let gridSpacing: CGFloat = 12
        return (screenWidth - totalPadding - gridSpacing) / 2
    }
    
    private var contentType: ContentType {
        ContentType(rawValue: item.contentType ?? "text") ?? .text
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 {
            return "now"
        } else if timeInterval < 3600 { // Less than 1 hour
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m"
        } else if timeInterval < 86400 { // Less than 1 day
            let hours = Int(timeInterval / 3600)
            return "\(hours)h"
        } else if timeInterval < 604800 { // Less than 1 week
            let days = Int(timeInterval / 86400)
            return "\(days)d"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
    
    private var contentTypeLabel: String {
        switch contentType {
        case .text: return "Text"
        case .url: return "Link"
        case .image: return "Image"
        }
    }
    
    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                // Header with content type and timestamp
                HStack {
                    Text(contentTypeLabel)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(formatTimestamp(item.timestamp ?? Date()))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(height: 24)
                .padding(.bottom, 12)
            
            // Content preview - takes remaining space
            if let content = item.content {
                switch contentType {
                case .text:
                    Text(content)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(6)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    
                case .url:
                    LinkPreviewCard(url: content)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                case .image:
                    // Show actual image
                    VStack(alignment: .leading, spacing: 0) {
                        if let imageData = Data(base64Encoded: content) {
                            if let uiImage = UIImage(data: imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 80)
                                    .clipped()
                                    .cornerRadius(8)
                            } else {
                                // Image error fallback
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.systemGray6))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 80)
                                    .overlay(
                                        VStack(spacing: 4) {
                                            Image(systemName: "photo.badge.exclamationmark")
                                                .font(.title3)
                                                .foregroundColor(.secondary)
                                            Text("Unable to load image")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    )
                            }
                        }
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            }
            .padding(16)
            .frame(width: cardWidth, height: 200)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
            
            // Selection circle overlay
            if isSelectionMode {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {}) {
                            ZStack {
                                Circle()
                                    .fill(isSelected ? Color.blue : Color.white)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle()
                                            .stroke(isSelected ? Color.blue : Color.gray.opacity(0.5), lineWidth: 2)
                                    )
                                
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.white)
                                        .font(.system(size: 12, weight: .bold))
                                }
                            }
                        }
                        .disabled(true) // Disable button action since tap is handled by parent
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
    }
    
    private func extractTitle(from url: URL) -> String {
        // Simple title extraction from URL
        if url.host?.contains("youtube.com") == true || url.host?.contains("youtu.be") == true {
            return "YouTube"
        } else if url.host?.contains("netflix.com") == true {
            return "Netflix"
        } else if url.host?.contains("github.com") == true {
            return "GitHub"
        } else {
            return url.host?.capitalized ?? "Website"
        }
    }
}

#Preview {
    // Create a sample ClipboardItem for preview
    let context = PersistenceController.preview.container.viewContext
    let sampleItem = ClipboardItem(context: context)
    sampleItem.content = "This is a sample text content for the clipboard item card preview."
    sampleItem.contentType = "text"
    sampleItem.timestamp = Date()
    
    return ClipboardItemCard(item: sampleItem, isLarge: false, isSelectionMode: true, isSelected: true)
        .environment(\.managedObjectContext, context)
} 