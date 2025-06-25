//
//  kopiApp.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import SwiftUI
import CloudKit
import AppKit

// AppDelegate to control app lifecycle
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide all windows immediately after launch
        for window in NSApplication.shared.windows {
            window.orderOut(nil)
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Don't automatically reopen windows when clicking dock icon (though we won't have one)
        return false
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when all windows are closed - keep running as menu bar app
        return false
    }
}

@main
struct kopiApp: App {
    // Add app delegate
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    let persistenceController = PersistenceController.shared
    @StateObject private var clipboardMonitor = ClipboardMonitor.shared
    @StateObject private var keyboardManager = KeyboardShortcutManager.shared
    @StateObject private var cloudKitManager = CloudKitManager.shared
    @StateObject private var menuBarManager = MenuBarManager.shared

    var body: some Scene {
        // We still need a WindowGroup for SwiftUI, but we'll prevent it from showing
        WindowGroup("Kopi", id: "main") {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(clipboardMonitor)
                .environmentObject(cloudKitManager)
                .environmentObject(menuBarManager)
                .onAppear {
                    setupApp()
                    // Immediately hide this window
                    hideDefaultWindow()
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 600)
        .defaultPosition(.center)
        // This window group exists but won't be shown by default
        .handlesExternalEvents(matching: Set(arrayLiteral: "main"))
    }
    
    private func hideDefaultWindow() {
        // Hide any automatically created windows
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows {
                if window.title == "Kopi" || window.title.isEmpty {
                    window.orderOut(nil)
                }
            }
        }
    }
    
    private func setupApp() {
        // Ensure menu bar manager is initialized
        _ = menuBarManager
        print("📋 MenuBarManager initialized")
        
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
