//
//  ContentView.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @StateObject private var dataManager = ClipboardDataManager.shared
    @StateObject private var keyboardShortcutManager = KeyboardShortcutManager.shared
    
    @State private var selectedFilter: SidebarFilter = .all
    @State private var searchText = ""
    @State private var contentTypeFilter: ContentType? = nil
    @State private var sortOrder: SortOrder = .newestFirst
    @State private var showingQuickPaste = false
    
    @State private var clipboardItems: [ClipboardItem] = []
    @State private var availableApps: [AppInfo] = []
    @State private var totalItemCount: Int = 0
    
    var filteredItems: [ClipboardItem] {
        var items = clipboardItems
        
        // Apply sidebar filter
        switch selectedFilter {
        case .all:
            // Show all items
            break
        case .app(let bundleID):
            items = items.filter { $0.sourceApp == bundleID }
        }
        
        // Apply search text filter
        if !searchText.isEmpty {
            items = items.filter { item in
                item.content?.localizedCaseInsensitiveContains(searchText) == true ||
                item.sourceAppName?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        
        // Apply content type filter
        if let contentTypeFilter = contentTypeFilter {
            items = items.filter { $0.contentType == contentTypeFilter.rawValue }
        }
        
        // Apply sorting
        switch sortOrder {
        case .newestFirst:
            items.sort { ($0.timestamp ?? Date.distantPast) > ($1.timestamp ?? Date.distantPast) }
        case .oldestFirst:
            items.sort { ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast) }
        case .byApp:
            items.sort { 
                if $0.sourceAppName == $1.sourceAppName {
                    return ($0.timestamp ?? Date.distantPast) > ($1.timestamp ?? Date.distantPast)
                }
                return ($0.sourceAppName ?? "") < ($1.sourceAppName ?? "")
            }
        }
        
        return items
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            SidebarView(
                selectedFilter: $selectedFilter,
                availableApps: availableApps,
                totalItemCount: totalItemCount
            )
            .onAppear {
                refreshData()
            }
        } detail: {
            // Main content area
            VStack(spacing: 0) {
                // Toolbar
                ToolbarView(
                    searchText: $searchText,
                    contentTypeFilter: $contentTypeFilter,
                    sortOrder: $sortOrder,
                    onRefresh: refreshData
                )
                
                Divider()
                
                // Grid view
                ClipboardGridView(
                    items: filteredItems,
                    onCopy: { item in
                        dataManager.copyToClipboard(item)
                    },
                    onDelete: { item in
                        dataManager.deleteClipboardItem(item)
                        refreshData()
                    },
                    onPin: { item in
                        dataManager.togglePin(for: item)
                        refreshData()
                    }
                )
            }
            .navigationTitle(titleForCurrentFilter)
        }
        .onAppear {
            setupKeyboardShortcuts()
            refreshData()
        }
        .onChange(of: selectedFilter) {
            refreshData()
        }
        .sheet(isPresented: $showingQuickPaste) {
            QuickPasteView()
        }
    }
    
    private var titleForCurrentFilter: String {
        switch selectedFilter {
        case .all:
            return "All Clipboard Items"
        case .app(let bundleID):
            let appName = availableApps.first(where: { $0.bundleID == bundleID })?.name ?? "Unknown App"
            return appName
        }
    }
    
    private func setupKeyboardShortcuts() {
        keyboardShortcutManager.onShortcutPressed = {
            DispatchQueue.main.async {
                showingQuickPaste = true
            }
        }
        keyboardShortcutManager.registerGlobalShortcut()
    }
    
    private func refreshData() {
        DispatchQueue.main.async {
            clipboardItems = dataManager.getRecentItems(limit: 500)
            availableApps = dataManager.getAppStatistics()
            totalItemCount = dataManager.getTotalItemCount()
        }
    }
}

// MARK: - Toolbar View

struct ToolbarView: View {
    @Binding var searchText: String
    @Binding var contentTypeFilter: ContentType?
    @Binding var sortOrder: SortOrder
    let onRefresh: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search clipboard items...", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
            )
            .frame(maxWidth: 300)
            
            Spacer()
            
            // Filter buttons
            HStack(spacing: 8) {
                // Content type filter
                Menu {
                    Button("All Types") {
                        contentTypeFilter = nil
                    }
                    
                    Divider()
                    
                    Button("Text") {
                        contentTypeFilter = .text
                    }
                    
                    Button("URLs") {
                        contentTypeFilter = .url
                    }
                    
                    Button("Images") {
                        contentTypeFilter = .image
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(contentTypeFilter?.rawValue.capitalized ?? "All Types")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                // Sort order
                Menu {
                    Button("Newest First") {
                        sortOrder = .newestFirst
                    }
                    
                    Button("Oldest First") {
                        sortOrder = .oldestFirst
                    }
                    
                    Button("By App") {
                        sortOrder = .byApp
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(sortOrder.displayName)
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                // Refresh button
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
    }
}

// MARK: - Quick Paste View

struct QuickPasteView: View {
    @StateObject private var dataManager = ClipboardDataManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var recentItems: [ClipboardItem] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Quick Paste")
                    .font(.headline)
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
            
            Divider()
            
            // Items list
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(recentItems.prefix(10).enumerated()), id: \.element.objectID) { index, item in
                        QuickPasteItemRow(
                            item: item,
                            number: index + 1,
                            onSelect: {
                                dataManager.copyToClipboard(item)
                                dismiss()
                            }
                        )
                    }
                }
            }
            .frame(maxHeight: 400)
        }
        .frame(width: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            recentItems = dataManager.getRecentItems(limit: 10)
        }
    }
}

struct QuickPasteItemRow: View {
    let item: ClipboardItem
    let number: Int
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Number badge
            Text("\(number)")
                .font(.caption.monospacedDigit())
                .fontWeight(.medium)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            
            // Content preview
            VStack(alignment: .leading, spacing: 2) {
                Text(item.content?.prefix(60) ?? "")
                    .lineLimit(1)
                    .font(.body)
                
                HStack {
                    if let appName = item.sourceAppName {
                        Text(appName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    ContentTypeBadge(contentType: ContentType(rawValue: item.contentType ?? "text") ?? .text)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(isHovered ? Color(NSColor.selectedControlColor).opacity(0.3) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - Sort Order

enum SortOrder: String, CaseIterable {
    case newestFirst = "newest"
    case oldestFirst = "oldest"
    case byApp = "app"
    
    var displayName: String {
        switch self {
        case .newestFirst: return "Newest First"
        case .oldestFirst: return "Oldest First"
        case .byApp: return "By App"
        }
    }
    
    var systemImage: String {
        switch self {
        case .newestFirst: return "arrow.down"
        case .oldestFirst: return "arrow.up"
        case .byApp: return "app.fill"
        }
    }
}

#Preview {
    ContentView()
}
