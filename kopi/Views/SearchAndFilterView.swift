//
//  SearchAndFilterView.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import SwiftUI

struct SearchAndFilterView: View {
    @Binding var searchText: String
    @Binding var selectedContentType: ContentType?
    @Binding var selectedApp: String?
    @Binding var showPinnedOnly: Bool
    @Binding var sortOrder: SortOrder
    
    let availableApps: [String]
    
    @State private var showingFilters = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search clipboard history...", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Button(action: { showingFilters.toggle() }) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(hasActiveFilters ? .accentColor : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Show filters")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
            )
            
            // Filters (collapsible)
            if showingFilters {
                VStack(spacing: 12) {
                    // Quick filters row
                    HStack {
                        // Content type filter
                        Picker("Content Type", selection: $selectedContentType) {
                            Text("All Types").tag(nil as ContentType?)
                            ForEach(ContentType.allCases, id: \.self) { type in
                                Label(type.displayName, systemImage: type.systemImage)
                                    .tag(type as ContentType?)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 120)
                        
                        // App filter
                        Picker("Source App", selection: $selectedApp) {
                            Text("All Apps").tag(nil as String?)
                            ForEach(availableApps, id: \.self) { app in
                                Text(app).tag(app as String?)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 150)
                        
                        Spacer()
                        
                        // Sort order
                        Picker("Sort", selection: $sortOrder) {
                            Label("Newest First", systemImage: "arrow.down")
                                .tag(SortOrder.newestFirst)
                            Label("Oldest First", systemImage: "arrow.up")
                                .tag(SortOrder.oldestFirst)
                            Label("By App", systemImage: "app.fill")
                                .tag(SortOrder.byApp)
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 120)
                    }
                    
                    // Toggle filters
                    HStack {
                        Toggle("Pinned only", isOn: $showPinnedOnly)
                            .toggleStyle(.checkbox)
                        
                        Spacer()
                        
                        // Clear all filters
                        if hasActiveFilters {
                            Button("Clear Filters") {
                                clearAllFilters()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Active filters summary
            if hasActiveFilters && !showingFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let contentType = selectedContentType {
                            FilterChip(
                                text: contentType.displayName,
                                systemImage: contentType.systemImage,
                                onRemove: { selectedContentType = nil }
                            )
                        }
                        
                        if let app = selectedApp {
                            FilterChip(
                                text: app,
                                systemImage: "app.fill",
                                onRemove: { selectedApp = nil }
                            )
                        }
                        
                        if showPinnedOnly {
                            FilterChip(
                                text: "Pinned",
                                systemImage: "pin.fill",
                                onRemove: { showPinnedOnly = false }
                            )
                        }
                        
                        if sortOrder != .newestFirst {
                            FilterChip(
                                text: sortOrder.displayName,
                                systemImage: sortOrder.systemImage,
                                onRemove: { sortOrder = .newestFirst }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
    }
    
    private var hasActiveFilters: Bool {
        selectedContentType != nil || selectedApp != nil || showPinnedOnly || sortOrder != .newestFirst
    }
    
    private func clearAllFilters() {
        selectedContentType = nil
        selectedApp = nil
        showPinnedOnly = false
        sortOrder = .newestFirst
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let text: String
    let systemImage: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2)
            Text(text)
                .font(.caption)
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.2))
        )
        .foregroundColor(.accentColor)
    }
}

 