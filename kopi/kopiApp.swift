//
//  kopiApp.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import SwiftUI
import CoreData
import CloudKit

@main
struct kopiApp: App {
    let persistenceController = PersistenceController.shared
    let deviceManager = DeviceManager.shared
    let cloudKitSyncManager = CloudKitSyncManager.shared
    let idResolver = IDResolver.shared
    let unifiedOperationsManager = UnifiedOperationsManager.shared
    // Phase 5 testing can be added here when needed
    @StateObject private var clipboardMonitor = ClipboardMonitor.shared
    @StateObject private var keyboardManager = KeyboardShortcutManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(clipboardMonitor)
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
        // Starting Unified Clipboard Sync System v2.0
        
        // Start clipboard monitoring
        clipboardMonitor.startMonitoring()
        
        // Register global keyboard shortcuts
        keyboardManager.registerGlobalShortcut()
        
        // Run startup diagnostics
        Task {
            await runStartupDiagnostics()
        }
        
        // Unified Clipboard Sync System ready
    }
    
    private func teardownApp() {
        // Shutting down Unified Clipboard Sync System
        
        // Stop monitoring
        clipboardMonitor.stopMonitoring()
        
        // Unregister shortcuts
        keyboardManager.unregisterGlobalShortcut()
        
        // Shutdown complete
    }
    
    // MARK: - Startup Diagnostics
    
    private func runStartupDiagnostics() async {
        // Running startup diagnostics silently...
        
        // Test device identification
        let deviceID = deviceManager.getDeviceID()
        // Device ID obtained
        
        // Test Core Data
        do {
            let context = persistenceController.container.viewContext
            let fetchRequest: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
            fetchRequest.fetchLimit = 1
            let _ = try context.fetch(fetchRequest)
            // Core Data connection verified
        } catch {
            print("❌ [App] Core Data connection failed: \(error)")
        }
        
        // Test CloudKit connectivity
        await testCloudKitConnectivity()
        
        // Startup diagnostics completed
    }
    
    private func testCloudKitConnectivity() async {
        await withCheckedContinuation { continuation in
            let container = CKContainer(identifier: "iCloud.com.wanmenzy.kopi-shared")
            
            // Simple account status check instead of querying records
            container.accountStatus { status, error in
                if let error = error {
                    print("❌ [App] CloudKit account check failed: \(error)")
                } else {
                    switch status {
                    case .available:
                        // CloudKit connectivity verified - account available
                        break
                    case .noAccount:
                        print("⚠️ [App] CloudKit account not signed in")
                    case .restricted:
                        print("⚠️ [App] CloudKit access restricted")
                    case .couldNotDetermine:
                        print("⚠️ [App] CloudKit status unknown")
                    case .temporarilyUnavailable:
                        print("⚠️ [App] CloudKit temporarily unavailable")
                    @unknown default:
                        print("⚠️ [App] Unknown CloudKit status")
                    }
                }
                continuation.resume()
            }
        }
    }
}
