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
    let onBatchDelete: ([ClipboardItem]) -> Void
    let onSave: (ClipboardItem, String) -> Void
    
    @State private var selectedItems: Set<NSManagedObjectID> = []
    @State private var lastSelectedItem: ClipboardItem?
    @State private var previewingItem: NSManagedObjectID?
    @FocusState private var isFocused: Bool
    
    // Drag selection support
    @State private var dragStartPoint: CGPoint?
    @State private var dragCurrentPoint: CGPoint?
    @State private var isDragging = false
    
    // Fixed grid columns - minimum 3 items per row
    private let cardSize: CGFloat = 200 // Fixed square size
    private let spacing: CGFloat = 12
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if items.isEmpty {
                    EmptyGridStateView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(40)
                } else {
                    LazyVGrid(columns: calculateColumns(for: geometry.size.width), alignment: .leading, spacing: spacing) {
                        ForEach(items, id: \.objectID) { item in
                            ClipboardItemCard(
                                item: item,
                                isSelected: selectedItems.contains(item.objectID),
                                cardSize: cardSize,
                                onCopy: { onCopy(item) },
                                onDelete: { onDelete(item) },
                                onSelect: { handleItemSelection(item) },
                                onPreview: { 
                                    previewingItem = item.objectID
                                },
                                onSave: onSave,
                                showingPreview: Binding(
                                    get: { previewingItem == item.objectID },
                                    set: { isShowing in
                                        if isShowing {
                                            previewingItem = item.objectID
                                        } else if previewingItem == item.objectID {
                                            previewingItem = nil
                                        }
                                    }
                                )
                            )
                            .onTapGesture {
                                handleItemTap(item)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .overlay(
                        // Drag selection overlay
                        dragSelectionOverlay
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        handleDragChanged(value)
                    }
                    .onEnded { _ in
                        handleDragEnded()
                    }
            )
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .onTapGesture {
            isFocused = true
        }
        .onChange(of: selectedItems) {
            // Ensure focus when items are selected
            if !selectedItems.isEmpty {
                isFocused = true
            }
        }
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }

    }
    
    // MARK: - Selection Handling
    
    private func handleItemSelection(_ item: ClipboardItem) {
        // Simple selection without modifiers
        if selectedItems.contains(item.objectID) {
            selectedItems.remove(item.objectID)
        } else {
            selectedItems.insert(item.objectID)
        }
        lastSelectedItem = item
    }
    
    private func handleItemTap(_ item: ClipboardItem) {
        let modifierFlags = NSEvent.modifierFlags
        
        if modifierFlags.contains(.command) {
            // Cmd+Click: Toggle selection
            if selectedItems.contains(item.objectID) {
                selectedItems.remove(item.objectID)
            } else {
                selectedItems.insert(item.objectID)
            }
        } else if modifierFlags.contains(.shift) && lastSelectedItem != nil {
            // Shift+Click: Range selection
            handleRangeSelection(to: item)
        } else {
            // Regular click: Single selection
            selectedItems = [item.objectID]
        }
        
        lastSelectedItem = item
    }
    
    private func handleRangeSelection(to endItem: ClipboardItem) {
        guard let startItem = lastSelectedItem,
              let startIndex = items.firstIndex(where: { $0.objectID == startItem.objectID }),
              let endIndex = items.firstIndex(where: { $0.objectID == endItem.objectID }) else {
            return
        }
        
        let range = min(startIndex, endIndex)...max(startIndex, endIndex)
        let itemsInRange = Array(items[range])
        
        for item in itemsInRange {
            selectedItems.insert(item.objectID)
        }
    }
    
    // MARK: - Drag Selection
    
    private func handleDragChanged(_ value: DragGesture.Value) {
        if dragStartPoint == nil {
            dragStartPoint = value.startLocation
            isDragging = true
        }
        dragCurrentPoint = value.location
        
        // Update selection based on drag rectangle
        updateDragSelection()
    }
    
    private func handleDragEnded() {
        dragStartPoint = nil
        dragCurrentPoint = nil
        isDragging = false
    }
    
    private func updateDragSelection() {
        guard let startPoint = dragStartPoint,
              let currentPoint = dragCurrentPoint else { return }
        
        let selectionRect = CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
        
        // This is a simplified approach - in a real implementation,
        // you'd need to calculate the actual card positions
        // For now, we'll just select items based on a simple heuristic
        let itemsPerRow = calculateColumns(for: 800).count // Use a reasonable default width
        let cardHeight = cardSize + spacing
        
        let startRow = max(0, Int(selectionRect.minY / cardHeight))
        let endRow = Int(selectionRect.maxY / cardHeight)
        let startCol = max(0, Int(selectionRect.minX / (cardSize + spacing)))
        let endCol = Int(selectionRect.maxX / (cardSize + spacing))
        
        for row in startRow...endRow {
            for col in startCol...endCol {
                let index = row * itemsPerRow + col
                if index >= 0 && index < items.count {
                    selectedItems.insert(items[index].objectID)
                }
            }
        }
    }
    
    @ViewBuilder
    private var dragSelectionOverlay: some View {
        if isDragging,
           let startPoint = dragStartPoint,
           let currentPoint = dragCurrentPoint {
            Rectangle()
                .stroke(Color.accentColor, lineWidth: 2)
                .background(Color.accentColor.opacity(0.1))
                .frame(
                    width: abs(currentPoint.x - startPoint.x),
                    height: abs(currentPoint.y - startPoint.y)
                )
                .position(
                    x: (startPoint.x + currentPoint.x) / 2,
                    y: (startPoint.y + currentPoint.y) / 2
                )
        }
    }
    
    // MARK: - Keyboard Handling
    
    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        switch keyPress.key {
        case .space:
            if let firstSelected = selectedItems.first,
               let item = items.first(where: { $0.objectID == firstSelected }) {
                previewingItem = item.objectID
                return .handled
            }
            return .ignored
            
        case .escape:
            if !selectedItems.isEmpty {
                selectedItems.removeAll()
                return .handled
            }
            return .ignored
            
        default:
            // Handle delete key by checking characters
            if keyPress.characters == String(UnicodeScalar(NSDeleteCharacter)!) {
                if !selectedItems.isEmpty {
                    deleteSelectedItems()
                    return .handled
                }
                return .ignored
            }
            
            // Check for Cmd+A manually
            if keyPress.characters == "a" && NSEvent.modifierFlags.contains(.command) {
                // Cmd+A: Select all
                selectedItems = Set(items.map { $0.objectID })
                return .handled
            }
            return .ignored
        }
    }
    
    // MARK: - Batch Operations
    
    private func deleteSelectedItems() {
        let itemsToDelete = items.filter { selectedItems.contains($0.objectID) }
        onBatchDelete(itemsToDelete)
        selectedItems.removeAll()
    }
    
    private func calculateColumns(for width: CGFloat) -> [GridItem] {
        let availableWidth = width - 32 // Account for horizontal padding (16px on each side)
        let itemWidth = cardSize + spacing
        let possibleColumns = Int(availableWidth / itemWidth)
        let columnCount = max(3, possibleColumns) // Minimum 3 columns
        
        return Array(repeating: GridItem(.fixed(cardSize), spacing: spacing), count: columnCount)
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