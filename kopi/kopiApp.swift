//
//  kopiApp.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import SwiftUI
import CloudKit

@main
struct kopiApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var clipboardMonitor = ClipboardMonitor.shared
    @StateObject private var keyboardManager = KeyboardShortcutManager.shared
    @StateObject private var cloudKitManager = CloudKitManager.shared
    @StateObject private var menuBarManager = MenuBarManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(clipboardMonitor)
                .environmentObject(cloudKitManager)
                .environmentObject(menuBarManager)
                .onAppear {
                    setupApp()
                }
                .onDisappear {
                    teardownApp()
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 600)
    }
    
    private func setupApp() {
        // Start monitoring
        clipboardMonitor.startMonitoring()
        
        // Register global keyboard shortcuts
        keyboardManager.registerGlobalShortcut()
        
        // Initialize CloudKit subscriptions
        Task {
            try? await cloudKitManager.subscribeToChanges()
        }
    }
    
    private func teardownApp() {
        // Stop monitoring
        clipboardMonitor.stopMonitoring()
        
        // Unregister shortcuts
        keyboardManager.unregisterGlobalShortcut()
    }
}
