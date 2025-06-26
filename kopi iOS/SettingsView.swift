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
                Section("Kopi Keyboard") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "keyboard")
                                .foregroundColor(.purple)
                            Text("Keyboard Extension")
                            Spacer()
                            Button("Setup") {
                                openKeyboardSettings()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Access your clipboard from any app:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("1.")
                                        .fontWeight(.medium)
                                        .foregroundColor(.blue)
                                    Text("Go to Settings > General > Keyboard > Keyboards")
                                }
                                
                                HStack {
                                    Text("2.")
                                        .fontWeight(.medium)
                                        .foregroundColor(.blue)
                                    Text("Add 'Kopi Keyboard'")
                                }
                                
                                HStack {
                                    Text("3.")
                                        .fontWeight(.medium)
                                        .foregroundColor(.blue)
                                    Text("Enable 'Allow Full Access'")
                                }
                                
                                HStack {
                                    Text("4.")
                                        .fontWeight(.medium)
                                        .foregroundColor(.blue)
                                    Text("Use the 🌐 button to switch keyboards")
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
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
                
                Section("About") {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.gray)
                        Text("Version")
                        Spacer()
                        Text("1.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "shield.checkerboard")
                            .foregroundColor(.green)
                        Text("Privacy")
                        Spacer()
                        Text("Local & iCloud Only")
                            .foregroundColor(.secondary)
                    }
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
    
    private func openKeyboardSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        
        if UIApplication.shared.canOpenURL(settingsUrl) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

#Preview {
    SettingsView()
} 