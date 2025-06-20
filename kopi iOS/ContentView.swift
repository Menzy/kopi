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
        TabView {
            ClipboardHistoryView()
                .tabItem {
                    Image(systemName: "doc.on.clipboard")
                    Text("History")
                }
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
        }
    }
}

struct ClipboardHistoryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var clipboardService: ClipboardService
    @State private var searchText = ""

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
            VStack {
                // Search bar
                SearchBar(text: $searchText)
                    .padding(.horizontal)
                
                if filteredItems.isEmpty {
                    EmptyStateView()
                } else {
                    List {
                        ForEach(filteredItems, id: \.id) { item in
                            ClipboardItemRow(item: item)
                                .onTapGesture {
                                    copyToPasteboard(item: item)
                                }
                        }
                        .onDelete(perform: deleteItems)
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Clipboard History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Clear All", role: .destructive) {
                            clearAllItems()
                        }
                        Button("Add Test Item") {
                            addTestItem()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private func copyToPasteboard(item: ClipboardItem) {
        guard let content = item.content else { return }
        
        // Notify clipboard service before copying to avoid loop
        clipboardService.notifyAppCopiedToClipboard(content: content)
        
        UIPasteboard.general.string = content
        
        // Show brief feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            let itemsToDelete = offsets.map { filteredItems[$0] }
            print("🗑️ [iOS] Deleting \(itemsToDelete.count) clipboard items")
            
            for item in itemsToDelete {
                let itemId = item.id?.uuidString ?? "unknown"
                let content = item.content?.prefix(50) ?? "no content"
                print("   - Deleting: \(itemId) - \(content)")
            }
            
            itemsToDelete.forEach(viewContext.delete)

            do {
                try viewContext.save()
                print("✅ [iOS] Deletion saved to CloudKit for \(itemsToDelete.count) items")
            } catch {
                let nsError = error as NSError
                print("❌ [iOS] Delete error: \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    private func clearAllItems() {
        withAnimation {
            let itemCount = filteredItems.count
            print("🗑️ [iOS] Clearing all \(itemCount) clipboard items")
            
            filteredItems.forEach(viewContext.delete)
            
            do {
                try viewContext.save()
                print("✅ [iOS] Clear all saved to CloudKit for \(itemCount) items")
            } catch {
                let nsError = error as NSError
                print("❌ [iOS] Clear error: \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    private func addTestItem() {
        let testContent = "Test clipboard item from iOS - \(Date().formatted(date: .abbreviated, time: .shortened))"
        
        // Notify clipboard service before copying to avoid loop
        clipboardService.notifyAppCopiedToClipboard(content: testContent)
        
        UIPasteboard.general.string = testContent
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
}

struct SettingsView: View {
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
                
                Section("Clipboard Monitoring") {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                            .foregroundColor(.orange)
                        Text("Auto-capture")
                        Spacer()
                        Text("Active")
                            .foregroundColor(.green)
                    }
                    
                    Text("Clipboard changes are monitored and saved automatically. Due to iOS limitations, monitoring frequency is reduced.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField("Search clipboard...", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    
    private var contentType: ContentType {
        ContentType(rawValue: item.contentType ?? "text") ?? .text
    }
    
    var body: some View {
        HStack {
            // Content type icon
            Image(systemName: contentType.systemImage)
                .foregroundColor(contentType.color)
                .frame(width: 20, height: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                // Content preview
                Text(item.contentPreview ?? "")
                    .font(.body)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                HStack {
                    // Source app
                    if let sourceAppName = item.sourceAppName {
                        Text(sourceAppName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Device origin
                    Text(item.deviceOrigin ?? "Unknown")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Timestamp
                    Text(item.timestamp ?? Date(), style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Pin indicator
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Clipboard History")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Your clipboard history will appear here when you copy items on any of your synced devices.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
