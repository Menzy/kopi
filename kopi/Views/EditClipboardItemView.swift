//
//  EditClipboardItemView.swift
//  kopi
//
//  Created by AI Assistant on 19/06/2025.
//

import SwiftUI

struct EditClipboardItemView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var unifiedOpsManager = UnifiedOperationsManager.shared
    
    let item: ClipboardItem
    @State private var editedContent: String = ""
    @State private var isEditing = false
    @State private var showingConflictResolution = false
    @State private var editResult: UnifiedOperationResult?
    @State private var editHistory: [EditVersion] = []
    @State private var showingHistory = false
    
    // Organization states
    @State private var isFavorite = false
    @State private var isPinned = false
    @State private var selectedCollections: Set<String> = []
    @State private var availableCollections = ["Work", "Personal", "Code Snippets", "URLs", "Images"]
    @State private var newCollectionName = ""
    @State private var showingNewCollection = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with item info
                headerView
                
                Divider()
                
                // Main content area
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Content editing section
                        contentEditingSection
                        
                        Divider()
                        
                        // Organization section
                        organizationSection
                        
                        Divider()
                        
                        // History section
                        historySection
                        
                        // Conflict resolution section
                        if showingConflictResolution {
                            conflictResolutionSection
                        }
                    }
                    .padding()
                }
                
                Divider()
                
                // Action buttons
                actionButtonsView
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            loadItemData()
        }
        .alert("Edit Result", isPresented: .constant(editResult != nil)) {
            Button("OK") { editResult = nil }
        } message: {
            Text(editResultMessage)
        }
        .sheet(isPresented: $showingHistory) {
            EditHistoryView(editHistory: editHistory)
        }
        .sheet(isPresented: $showingNewCollection) {
            NewCollectionView(collectionName: $newCollectionName) {
                if !newCollectionName.isEmpty {
                    availableCollections.append(newCollectionName)
                    selectedCollections.insert(newCollectionName)
                    newCollectionName = ""
                }
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Clipboard Item")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if let canonicalID = item.canonicalID {
                    Text("ID: \(canonicalID.uuidString.prefix(8))...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 12) {
                    Label(item.deviceOrigin ?? "Unknown", systemImage: "laptopcomputer")
                    Label(item.contentType ?? "text", systemImage: "doc.text")
                    if let timestamp = item.timestamp {
                        Label(RelativeDateTimeFormatter().localizedString(for: timestamp, relativeTo: Date()),
                              systemImage: "clock")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status indicators
            HStack(spacing: 8) {
                if isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                }
                if isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundColor(.orange)
                }
                if unifiedOpsManager.isProcessingOperations {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        .padding()
    }
    
    private var contentEditingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Content")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { showingHistory = true }) {
                    Label("History (\(editHistory.count))", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.borderless)
                .disabled(editHistory.isEmpty)
            }
            
            TextEditor(text: $editedContent)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 200)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            
            HStack {
                Text("\(editedContent.count) characters")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if editedContent != (item.content ?? "") {
                    Text("Modified")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(4)
                }
            }
        }
    }
    
    private var organizationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Organization")
                .font(.headline)
            
            HStack(spacing: 16) {
                Button(action: toggleFavorite) {
                    Label(isFavorite ? "Unfavorite" : "Favorite",
                          systemImage: isFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.bordered)
                .tint(isFavorite ? .yellow : .primary)
                
                Button(action: togglePin) {
                    Label(isPinned ? "Unpin" : "Pin",
                          systemImage: isPinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.bordered)
                .tint(isPinned ? .orange : .primary)
            }
            
            // Collections
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Collections")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Button("New Collection") {
                        showingNewCollection = true
                    }
                    .buttonStyle(.borderless)
                }
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach(availableCollections, id: \.self) { collection in
                        CollectionToggle(
                            name: collection,
                            isSelected: selectedCollections.contains(collection)
                        ) {
                            toggleCollection(collection)
                        }
                    }
                }
            }
        }
    }
    
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Changes")
                .font(.headline)
            
            if editHistory.isEmpty {
                Text("No edit history available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(editHistory.suffix(3).reversed(), id: \.version) { version in
                    EditVersionRow(version: version)
                }
                
                if editHistory.count > 3 {
                    Button("View All History (\(editHistory.count) versions)") {
                        showingHistory = true
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
    
    private var conflictResolutionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conflict Resolution")
                .font(.headline)
                .foregroundColor(.red)
            
            Text("This item has conflicting edits from multiple devices. Choose how to resolve:")
                .font(.subheadline)
            
            HStack(spacing: 12) {
                Button("Use Local") {
                    resolveConflict(.useLocal)
                }
                .buttonStyle(.bordered)
                
                Button("Use Remote") {
                    resolveConflict(.useRemote)
                }
                .buttonStyle(.bordered)
                
                Button("Merge") {
                    resolveConflict(.merge)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var actionButtonsView: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            Button("Revert Changes") {
                editedContent = item.content ?? ""
            }
            .buttonStyle(.bordered)
            .disabled(editedContent == (item.content ?? ""))
            
            Button("Save Changes") {
                saveChanges()
            }
            .buttonStyle(.borderedProminent)
            .disabled(editedContent == (item.content ?? "") || unifiedOpsManager.isProcessingOperations)
        }
        .padding()
    }
    
    private var editResultMessage: String {
        guard let result = editResult else { return "" }
        
        switch result {
        case .success:
            return "Changes saved successfully and synced across all devices."
        case .failure(_, let error):
            return "Failed to save changes: \(error.localizedDescription)"
        case .conflict(_, let conflictType):
            switch conflictType {
            case .editConflict(let local, let remote):
                return "Edit conflict detected. Local version: \(local), Remote version: \(remote)"
            default:
                return "Conflict detected: \(conflictType)"
            }
        case .pending:
            return "Changes are being processed..."
        }
    }
    
    // MARK: - Actions
    
    private func loadItemData() {
        editedContent = item.content ?? ""
        isFavorite = item.isFavorite
        isPinned = item.isPinned
        
        if let collections = item.collections {
            selectedCollections = Set(collections.components(separatedBy: ",").filter { !$0.isEmpty })
        }
        
        if let canonicalID = item.canonicalID {
            editHistory = unifiedOpsManager.getEditHistory(canonicalID: canonicalID)
        }
    }
    
    private func saveChanges() {
        guard let canonicalID = item.canonicalID else { return }
        
        Task {
            let result = await unifiedOpsManager.editClipboardItem(
                canonicalID: canonicalID,
                newContent: editedContent
            )
            
            await MainActor.run {
                self.editResult = result
                
                if case .success = result {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                } else if case .conflict = result {
                    showingConflictResolution = true
                }
            }
        }
    }
    
    private func toggleFavorite() {
        guard let canonicalID = item.canonicalID else { return }
        
        Task {
            let result = await unifiedOpsManager.toggleFavorite(canonicalID: canonicalID)
            
            await MainActor.run {
                if case .success = result {
                    isFavorite.toggle()
                }
            }
        }
    }
    
    private func togglePin() {
        guard let canonicalID = item.canonicalID else { return }
        
        Task {
            let result = await unifiedOpsManager.togglePin(canonicalID: canonicalID)
            
            await MainActor.run {
                if case .success = result {
                    isPinned.toggle()
                }
            }
        }
    }
    
    private func toggleCollection(_ collection: String) {
        guard let canonicalID = item.canonicalID else { return }
        
        let isCurrentlySelected = selectedCollections.contains(collection)
        
        Task {
            let result: UnifiedOperationResult
            
            if isCurrentlySelected {
                result = await unifiedOpsManager.removeFromCollection(canonicalID: canonicalID, collectionName: collection)
            } else {
                result = await unifiedOpsManager.addToCollection(canonicalID: canonicalID, collectionName: collection)
            }
            
            await MainActor.run {
                if case .success = result {
                    if isCurrentlySelected {
                        selectedCollections.remove(collection)
                    } else {
                        selectedCollections.insert(collection)
                    }
                }
            }
        }
    }
    
    private func resolveConflict(_ strategy: ConflictResolutionStrategy) {
        guard let canonicalID = item.canonicalID else { return }
        
        Task {
            let result = await unifiedOpsManager.resolveEditConflict(
                canonicalID: canonicalID,
                strategy: strategy
            )
            
            await MainActor.run {
                showingConflictResolution = false
                editResult = result
                
                if case .success = result {
                    loadItemData() // Reload with resolved content
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct CollectionToggle: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                Text(name)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.borderless)
    }
}

struct EditVersionRow: View {
    let version: EditVersion
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Version \(version.version)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(version.deviceID)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(version.timestamp.formatted(.relative(presentation: .named)))
                    .font(.caption)
                
                Text(version.editType.description)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(3)
            }
        }
        .padding(.vertical, 4)
    }
}

struct EditHistoryView: View {
    let editHistory: [EditVersion]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List(editHistory.reversed(), id: \.version) { version in
                EditVersionRow(version: version)
            }
            .navigationTitle("Edit History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct NewCollectionView: View {
    @Binding var collectionName: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                TextField("Collection Name", text: $collectionName)
                    .textFieldStyle(.roundedBorder)
                
                Spacer()
            }
            .padding()
            .navigationTitle("New Collection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .disabled(collectionName.isEmpty)
                }
            }
        }
    }
}

extension EditType {
    var description: String {
        switch self {
        case .contentChange: return "Content"
        case .organizationChange: return "Organization"
        case .metadataChange: return "Metadata"
        }
    }
}

#Preview {
    let item = ClipboardItem()
    item.content = "Sample clipboard content for editing"
    item.canonicalID = UUID()
    item.timestamp = Date()
    item.deviceOrigin = "macOS"
    
    return EditClipboardItemView(item: item)
} 