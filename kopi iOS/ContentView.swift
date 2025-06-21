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
                                    if !isSelectionMode {
                                        Button("Copy") {
                                            copyItem(item)
                                        }
                                        Button("Delete", role: .destructive) {
                                            deleteItem(item)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .navigationTitle(isSelectionMode ? "\(selectedItems.count) Selected" : "Clipboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if isSelectionMode {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            exitSelectionMode()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button("Select All") {
                                selectAll()
                            }
                            
                            Divider()
                            
                            Button("Copy", systemImage: "doc.on.doc") {
                                copySelectedItems()
                            }
                            .disabled(selectedItems.isEmpty)
                            
                            Button("Share", systemImage: "square.and.arrow.up") {
                                shareSelectedItems()
                            }
                            .disabled(selectedItems.isEmpty)
                            
                            Divider()
                            
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                deleteSelectedItems()
                            }
                            .disabled(selectedItems.isEmpty)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.title2)
                        }
                    }
                } else {
                    ToolbarItem(placement: .navigationBarTrailing) {
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
    
    private func selectAll() {
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedItems = Set(filteredItems.map { $0.objectID })
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
            itemsToDelete.forEach(viewContext.delete)
            
            do {
                try viewContext.save()
                exitSelectionMode()
            } catch {
                print("Error deleting selected items: \(error)")
            }
        }
    }
}



#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
