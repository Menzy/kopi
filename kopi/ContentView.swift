//
//  ContentView.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var dataManager = ClipboardDataManager.shared
    @EnvironmentObject private var clipboardMonitor: ClipboardMonitor

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ClipboardItem.timestamp, ascending: false)],
        predicate: NSPredicate(format: "isTransient == NO"),
        animation: .default)
    private var clipboardItems: FetchedResults<ClipboardItem>

    var body: some View {
        NavigationView {
            VStack {
                if clipboardItems.isEmpty {
                    EmptyStateView()
                } else {
                    List {
                        ForEach(clipboardItems, id: \.id) { item in
                            ClipboardItemRow(item: item)
                        }
                        .onDelete(perform: deleteItems)
                    }
                }
            }
                        .navigationTitle("Clipboard History")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: toggleMonitoring) {
                        Label(
                            clipboardMonitor.isMonitoring ? "Stop Monitoring" : "Start Monitoring",
                            systemImage: clipboardMonitor.isMonitoring ? "pause.circle" : "play.circle"
                        )
                    }
                    .foregroundColor(clipboardMonitor.isMonitoring ? .red : .green)
                    
                    Button(action: addTestItem) {
                        Label("Add Test Item", systemImage: "plus")
                    }
                    
                    Button(action: clearAll) {
                        Label("Clear All", systemImage: "trash")
                    }
                    .disabled(clipboardItems.isEmpty)
                }
                
                ToolbarItemGroup(placement: .status) {
                    HStack {
                        Circle()
                            .fill(clipboardMonitor.isMonitoring ? .green : .gray)
                            .frame(width: 8, height: 8)
                        Text(clipboardMonitor.isMonitoring ? "Monitoring" : "Stopped")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func addTestItem() {
        let testContent = "Test clipboard item - \(Date().formatted())"
        _ = dataManager.createClipboardItem(
            content: testContent,
            contentType: .text,
            sourceApp: "com.apple.finder",
            sourceAppName: "Finder"
        )
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { clipboardItems[$0] }.forEach { item in
                dataManager.deleteClipboardItem(item)
            }
        }
    }
    
        private func clearAll() {
        withAnimation {
            clipboardItems.forEach { item in
                dataManager.deleteClipboardItem(item)
            }
        }
    }
    
    private func toggleMonitoring() {
        if clipboardMonitor.isMonitoring {
            clipboardMonitor.stopMonitoring()
        } else {
            clipboardMonitor.startMonitoring()
        }
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    @StateObject private var dataManager = ClipboardDataManager.shared
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: contentType.systemImage)
                        .foregroundColor(.secondary)
                    
                    Text(contentType.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                    
                    Spacer()
                    
                    Text(item.timestamp?.formatted(.relative(presentation: .named)) ?? "Unknown")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(item.contentPreview ?? item.content ?? "No content")
                    .lineLimit(2)
                    .font(.body)
                
                if let sourceAppName = item.sourceAppName {
                    HStack {
                        // Show app icon if available, otherwise use system icon
                        if let iconData = item.sourceAppIcon,
                           let nsImage = NSImage(data: iconData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "app")
                                .font(.caption2)
                        }
                        
                        Text(sourceAppName)
                            .font(.caption2)
                        Spacer()
                        Text(item.deviceOrigin ?? "Unknown")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: {
                dataManager.togglePin(for: item)
            }) {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .foregroundColor(item.isPinned ? .orange : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Copy to Clipboard") {
                copyToClipboard()
            }
            
            Button(item.isPinned ? "Unpin" : "Pin") {
                dataManager.togglePin(for: item)
            }
            
            Divider()
            
            Button("Delete", role: .destructive) {
                dataManager.deleteClipboardItem(item)
            }
        }
    }
    
    private var contentType: ContentType {
        ContentType(rawValue: item.contentType ?? "text") ?? .text
    }
    
    private func copyToClipboard() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.content ?? "", forType: .string)
        #endif
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Clipboard History")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Your clipboard history will appear here")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
