//
//  ContentView.swift
//  kopi ios
//
//  Created by Wan Menzy on 20/06/2025.
//

import SwiftUI
import CoreData

struct ContentView: View {
    var body: some View {
        ClipboardHistoryView()
    }
}

struct ClipboardHistoryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var clipboardService: ClipboardService
    @State private var searchText = ""
    @State private var showingSettings = false

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ClipboardItem.timestamp, ascending: false)],
        animation: .default)
    private var clipboardItems: FetchedResults<ClipboardItem>

    var filteredItems: [ClipboardItem] {
        if searchText.isEmpty {
            return Array(clipboardItems)
        } else {
            return clipboardItems.filter { item in
                item.content?.localizedCaseInsensitiveContains(searchText) == true ||
                item.sourceAppName?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search clipboard history", text: $searchText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                
                // Main content
                if filteredItems.isEmpty {
                    EmptyStateView()
                } else {
                    ScrollView {
                        let screenWidth = UIScreen.main.bounds.width
                        let totalPadding: CGFloat = 32 // 16 on each side
                        let gridSpacing: CGFloat = 12
                        let cardWidth = (screenWidth - totalPadding - gridSpacing) / 2
                        
                        LazyVGrid(columns: [
                            GridItem(.fixed(cardWidth)),
                            GridItem(.fixed(cardWidth))
                        ], spacing: 16) {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                ClipboardItemCard(item: item, isLarge: shouldUseLargeCard(for: item, at: index))
                                    .frame(width: cardWidth)
                                    .contextMenu {
                                        Button("Copy") {
                                            copyItem(item)
                                        }
                                        Button("Delete", role: .destructive) {
                                            deleteItem(item)
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .navigationTitle("Clipboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Settings") {
                            showingSettings = true
                        }
                        
                        Divider()
                        
                        Button("Clear All", role: .destructive) {
                            clearAllItems()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
    
    private func shouldUseLargeCard(for item: ClipboardItem, at index: Int) -> Bool {
        let contentType = ContentType(rawValue: item.contentType ?? "text") ?? .text
        // Make URL cards larger, and vary some text cards
        return contentType == .url || (contentType == .text && index % 3 == 0)
    }
    
    private func copyItem(_ item: ClipboardItem) {
        if let content = item.content {
            UIPasteboard.general.string = content
        }
    }

    private func deleteItem(_ item: ClipboardItem) {
        withAnimation {
            viewContext.delete(item)
            
            do {
                try viewContext.save()
            } catch {
                print("Error deleting item: \(error)")
            }
        }
    }
    
    private func clearAllItems() {
        withAnimation {
            clipboardItems.forEach(viewContext.delete)
            
            do {
                try viewContext.save()
            } catch {
                print("Error clearing clipboard items: \(error)")
            }
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var clipboardService: ClipboardService
    
    var body: some View {
        NavigationView {
            List {
                Section("About") {
                    HStack {
                        Text("App Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Platform")
                        Spacer()
                        Text("iOS")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Data Sync") {
                    HStack {
                        Image(systemName: "icloud")
                            .foregroundColor(.blue)
                        Text("iCloud Sync")
                        Spacer()
                        Text("Enabled")
                            .foregroundColor(.green)
                    }
                    
                    Text("Your clipboard history syncs automatically across all your devices using iCloud.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ClipboardItemCard: View {
    let item: ClipboardItem
    let isLarge: Bool
    
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
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
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



struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Clipboard History")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Copy something on your Mac to see it appear here automatically.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
