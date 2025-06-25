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
    @State private var isSelectionMode = false
    @State private var selectedItems: Set<NSManagedObjectID> = []

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)],
        animation: .default)
    private var clipboardItems: FetchedResults<ClipboardItem>

    var filteredItems: [ClipboardItem] {
        let items = if searchText.isEmpty {
            Array(clipboardItems)
        } else {
            clipboardItems.filter { item in
                item.content?.localizedCaseInsensitiveContains(searchText) == true ||
                item.sourceAppName?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        
        // Deduplicate by objectID to prevent duplicate UI items
        var seen = Set<NSManagedObjectID>()
        return items.filter { item in
            let isNew = seen.insert(item.objectID).inserted
            return isNew
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom header with title and menu
                HStack {
                    Text(isSelectionMode ? "\(selectedItems.count) Selected" : "Clipboard")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    if !isSelectionMode {
                        Menu {
                            Button("Select", systemImage: "checkmark.circle") {
                                enterSelectionMode()
                            }
                            
                            Button("Settings", systemImage: "gear") {
                                showingSettings = true
                            }
                            
                            Divider()
                            
                            Button("Clear All", systemImage: "trash", role: .destructive) {
                                clearAllItems()
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.title2)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                
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
                            ForEach(Array(filteredItems.enumerated()), id: \.element.objectID) { index, item in
                                ClipboardItemCard(
                                    item: item, 
                                    isLarge: shouldUseLargeCard(for: item, at: index),
                                    isSelectionMode: isSelectionMode,
                                    isSelected: selectedItems.contains(item.objectID)
                                )
                                .frame(width: cardWidth)
                                .onTapGesture {
                                    if isSelectionMode {
                                        toggleSelection(for: item)
                                    }
                                }
                                .contextMenu {
                                    if item.contentType == ContentType.url.rawValue, let urlString = item.content, let url = URL(string: urlString) {
                                        Button("Open in Browser", systemImage: "safari") {
                                            UIApplication.shared.open(url)
                                        }
                                    }

                                    Button("Select", systemImage: "checkmark.circle") {
                                        enterSelectionMode()
                                        toggleSelection(for: item)
                                    }

                                    Divider()

                                    Button("Copy", systemImage: "doc.on.doc") {
                                        copyItem(item)
                                    }
                                    
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        deleteItem(item)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isSelectionMode {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(allItemsSelected ? "Deselect All" : "Select All") {
                            toggleSelectAll()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            exitSelectionMode()
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelectionMode {
                    HStack(spacing: 0) {
                        Button(action: {
                            copySelectedItems()
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.title2)
                                Text("Copy")
                                    .font(.caption)
                            }
                            .foregroundColor(selectedItems.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(selectedItems.isEmpty)
                        
                        Button(action: {
                            shareSelectedItems()
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.title2)
                                Text("Share")
                                    .font(.caption)
                            }
                            .foregroundColor(selectedItems.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(selectedItems.isEmpty)
                        
                        Button(action: {
                            deleteSelectedItems()
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.title2)
                                Text("Delete")
                                    .font(.caption)
                            }
                            .foregroundColor(selectedItems.isEmpty ? .secondary : .red)
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(selectedItems.isEmpty)
                    }
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))
                    .overlay(
                        Rectangle()
                            .frame(height: 0.5)
                            .foregroundColor(Color(.separator)),
                        alignment: .top
                    )
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
        // Phase 4: Use ClipboardService method which handles tracking
        clipboardService.copyToClipboard(item)
    }

    private func deleteItem(_ item: ClipboardItem) {
        withAnimation {
            // Use ClipboardService which handles CloudKit deletion
            clipboardService.deleteClipboardItem(item)
        }
    }
    
    private func clearAllItems() {
        withAnimation {
            // Use ClipboardService which handles CloudKit deletion
            let allItems = Array(clipboardItems)
            clipboardService.deleteClipboardItems(allItems)
        }
    }
    
    // MARK: - Selection Methods
    
    private func enterSelectionMode() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isSelectionMode = true
            selectedItems.removeAll()
        }
    }
    
    private func exitSelectionMode() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isSelectionMode = false
            selectedItems.removeAll()
        }
    }
    
    private func toggleSelection(for item: ClipboardItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedItems.contains(item.objectID) {
                selectedItems.remove(item.objectID)
            } else {
                selectedItems.insert(item.objectID)
            }
        }
    }
    
    private var allItemsSelected: Bool {
        !filteredItems.isEmpty && selectedItems.count == filteredItems.count
    }
    
    private func toggleSelectAll() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if allItemsSelected {
                selectedItems.removeAll()
            } else {
                selectedItems = Set(filteredItems.map { $0.objectID })
            }
        }
    }
    
    private func copySelectedItems() {
        let selectedContents = filteredItems
            .filter { selectedItems.contains($0.objectID) }
            .compactMap { $0.content }
            .joined(separator: "\n\n")
        
        if !selectedContents.isEmpty {
            UIPasteboard.general.string = selectedContents
            exitSelectionMode()
        }
    }
    
    private func shareSelectedItems() {
        let selectedContents = filteredItems
            .filter { selectedItems.contains($0.objectID) }
            .compactMap { $0.content }
        
        if !selectedContents.isEmpty {
            let activityViewController = UIActivityViewController(
                activityItems: selectedContents,
                applicationActivities: nil
            )
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(activityViewController, animated: true)
            }
            
            exitSelectionMode()
        }
    }
    
    private func deleteSelectedItems() {
        withAnimation {
            let itemsToDelete = filteredItems.filter { selectedItems.contains($0.objectID) }
            // Use ClipboardService which handles CloudKit deletion
            clipboardService.deleteClipboardItems(itemsToDelete)
            exitSelectionMode()
        }
    }
}



#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
