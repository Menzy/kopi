//
//  kopi_iosApp.swift
//  kopi ios
//
//  Created by Wan Menzy on 20/06/2025.
//

import SwiftUI
import BackgroundTasks

@main
struct kopi_iosApp: App {
    let persistenceController = PersistenceController.shared
    let deviceManager = DeviceManager.shared
    let cloudKitSyncManager = CloudKitSyncManager.shared
    let idResolver = IDResolver.shared
    let unifiedOperationsManager = UnifiedOperationsManager.shared
    @StateObject private var clipboardService = ClipboardService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(clipboardService)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didFinishLaunchingNotification)) { _ in
                    // Register background tasks on app launch
                    registerBackgroundTasks()
                }
        }
    }
    
    private func registerBackgroundTasks() {
        // This is handled in ClipboardService init, but we can add additional setup here if needed
        print("📱 [iOS] App launched - background tasks registered")
    }
}
