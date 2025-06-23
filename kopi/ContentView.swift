//
//  ContentView.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import SwiftUI
import CoreData
import Combine

struct ContentView: View {
    @StateObject private var dataManager = ClipboardDataManager.shared
    @StateObject private var keyboardShortcutManager = KeyboardShortcutManager.shared
    @EnvironmentObject private var clipboardMonitor: ClipboardMonitor
    
    @State private var selectedFilter: SidebarFilter = .all
    @State private var searchText = ""
    @State private var showingQuickPaste = false
    
    @State private var clipboardItems: [ClipboardItem] = []
    @State private var availableApps: [AppInfo] = []
    @State private var totalItemCount: Int = 0
    @State private var contentTypeCounts: [ContentType: Int] = [:]

    var filteredItems: [ClipboardItem] {
        var items = clipboardItems
        
        // Apply sidebar filter
        switch selectedFilter {
        case .all:
            // Show all items
            break
        case .contentType(let contentType):
            items = items.filter { $0.contentType == contentType.rawValue }
        case .app(let bundleID):
            items = items.filter { $0.sourceAppBundleID == bundleID }
        }
        
        // Apply search text filter
        if !searchText.isEmpty {
            items = items.filter { item in
                item.content?.localizedCaseInsensitiveContains(searchText) == true ||
                item.sourceAppName?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        
        // Sort by newest first (default behavior)
        items.sort { ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) }
        
        return items
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar
            SidebarView(
                selectedFilter: $selectedFilter,
                availableApps: availableApps,
                totalItemCount: totalItemCount,
                contentTypeCounts: contentTypeCounts
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
                    onBatchDelete: { items in
                        dataManager.deleteClipboardItems(items)
                        refreshData()
                    },
                    onSave: { item, newContent in
                        dataManager.updateClipboardItem(item, content: newContent)
                        refreshData()
                    }
                )
            }
            .navigationTitle(titleForCurrentFilter)
        }
        .frame(minWidth: 680, minHeight: 400) // Minimum size for 3 cards (200*3 + spacing + sidebar)
        .onAppear {
            setupKeyboardShortcuts()
            refreshData()
        }
        .onChange(of: selectedFilter) {
            refreshData()
        }
        .onChange(of: clipboardMonitor.clipboardDidChange) {
            // Auto-refresh when clipboard changes
            refreshData()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Force immediate clipboard check and refresh when app becomes active
            clipboardMonitor.forceCheck()
            refreshData()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // Force immediate clipboard check and refresh when window gains focus
            clipboardMonitor.forceCheck()
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
        case .contentType(let contentType):
            return contentType.displayName
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
            
            // Calculate content type counts
            var typeCounts: [ContentType: Int] = [:]
            for item in clipboardItems {
                if let contentTypeString = item.contentType,
                   let contentType = ContentType(rawValue: contentTypeString) {
                    typeCounts[contentType, default: 0] += 1
                }
            }
            contentTypeCounts = typeCounts
        }
    }
}

// MARK: - Toolbar View

struct ToolbarView: View {
    @Binding var searchText: String
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
            
            // Refresh button
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
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

#Preview {
    ContentView()
}
