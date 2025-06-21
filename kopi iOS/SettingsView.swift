//
//  SettingsView.swift
//  kopi ios
//
//  Created by Wan Menzy on 20/06/2025.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var clipboardService: ClipboardService
    
    var body: some View {
        NavigationView {
            List {
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
} 