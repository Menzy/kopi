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
            VStack(spacing: 0) {
                // Main content
                if filteredItems.isEmpty {
                    EmptyStateView()
                } else {
                    List {
                        ForEach(filteredItems, id: \.id) { item in
                            ClipboardItemRow(item: item)
                        }
                        .onDelete(perform: deleteItems)
                    }
                    .searchable(text: $searchText, prompt: "Search clipboard history")
                }
            }
            .navigationTitle("Clipboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Clear All", role: .destructive) {
                            clearAllItems()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { filteredItems[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                // Handle error appropriately
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
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
}

struct SettingsView: View {
    @EnvironmentObject private var clipboardService: ClipboardService
    
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
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    
    private var contentType: ContentType {
        ContentType(rawValue: item.contentType ?? "text") ?? .text
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 {
            return "now"
        } else if timeInterval < 3600 { // Less than 1 hour
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m ago"
        } else if timeInterval < 86400 { // Less than 1 day
            let hours = Int(timeInterval / 3600)
            return "\(hours)h ago"
        } else if timeInterval < 604800 { // Less than 1 week
            let days = Int(timeInterval / 86400)
            return "\(days)d ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
    
    var body: some View {
        HStack {
            // Content type icon
            Image(systemName: contentType.systemImage)
                .foregroundColor(contentType.color)
                .frame(width: 20, height: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                // Content preview
                Text(item.content ?? "")
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
                    
                    // Timestamp
                    Text(formatTimestamp(item.timestamp ?? Date()))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Clipboard History")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Copy something on your Mac to see it appear here automatically.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
