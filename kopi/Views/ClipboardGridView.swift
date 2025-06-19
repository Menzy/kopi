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
    
    @State private var selectedItem: ClipboardItem?
    @Binding var previewItem: ClipboardItem?
    @Binding var showingPreview: Bool
    @FocusState private var isFocused: Bool
    
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
                    LazyVGrid(columns: calculateColumns(for: geometry.size.width), spacing: spacing) {
                        ForEach(items, id: \.objectID) { item in
                                                    ClipboardItemCard(
                            item: item,
                            isSelected: selectedItem?.objectID == item.objectID,
                            cardSize: cardSize,
                            onCopy: { onCopy(item) },
                            onDelete: { onDelete(item) },
                            onPin: { onPin(item) },
                            onSelect: { selectedItem = item },
                            onPreview: { 
                                previewItem = item
                                showingPreview = true
                            }
                        )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
                }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear {
            isFocused = true
        }
        .onKeyPress { keyPress in
            if keyPress.key == .space, let selected = selectedItem {
                previewItem = selected
                showingPreview = true
                return .handled
            }
            return .ignored
        }
    }
    
    private func calculateColumns(for width: CGFloat) -> [GridItem] {
        let availableWidth = width - 40 // Account for horizontal padding
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