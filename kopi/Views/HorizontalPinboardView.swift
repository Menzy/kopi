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
    @EnvironmentObject private var clipboardMonitor: ClipboardMonitor
    @State private var clipboardItems: [ClipboardItem] = []
    @State private var hoveredItem: NSManagedObjectID?
    
    private let itemWidth: CGFloat = 180   // Card width
    private let itemHeight: CGFloat = 180  // Card height for better horizontal layout
    private let spacing: CGFloat = 20      // More spacing
    
    var body: some View {
        VStack(spacing: 0) {
            // Horizontal scrollable content
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(clipboardItems.prefix(20), id: \.objectID) { item in
                        ClipboardItemCard(
                            item: item,
                            isSelected: hoveredItem == item.objectID,
                            cardSize: itemWidth,
                            onCopy: {
                                dataManager.copyToClipboard(item)
                                onDismiss() // Auto-dismiss after copying
                            },
                            onDelete: {
                                dataManager.deleteClipboardItem(item)
                                refreshData()
                            },
                            onSelect: {
                                hoveredItem = item.objectID
                            },
                            onPreview: {
                                // Preview functionality can be added later if needed
                            },
                            onSave: { _, _ in
                                // Save functionality can be added later if needed
                            },
                            showingPreview: .constant(false)
                        )
                        .frame(width: itemWidth, height: itemHeight) // Override the square constraint
                        .clipped() // Ensure content doesn't overflow
                        .onHover { isHovering in
                            hoveredItem = isHovering ? item.objectID : nil
                        }
                    }
                }
                .padding(.horizontal, 20)  // Horizontal padding
                .padding(.vertical, 12)    // Reduced vertical padding
            }
            .frame(height: itemHeight + 48) // Adjusted height for reduced vertical padding
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        )
        .padding(.horizontal, 20)  // Horizontal padding around component
        .padding(.vertical, 12)     // Reduced vertical padding around component
        .onAppear {
            refreshData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardDidChange)) { _ in
            refreshData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudKitSyncCompleted)) { _ in
            // Refresh when CloudKit sync completes (including deletions/modifications)
            refreshData()
        }
        .onChange(of: clipboardMonitor.clipboardDidChange) {
            // Also listen to the same property that ContentView uses
            refreshData()
        }
    }
    
    private func refreshData() {
        clipboardItems = dataManager.getRecentItems(limit: 20)
    }
}