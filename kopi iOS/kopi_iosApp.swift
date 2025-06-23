//
//  kopi_iosApp.swift
//  kopi ios
//
//  Created by Wan Menzy on 20/06/2025.
//

import SwiftUI
import BackgroundTasks
import CloudKit

@main
struct kopi_iosApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var clipboardService = ClipboardService()
    @StateObject private var cloudKitManager = CloudKitManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(clipboardService)
                .environmentObject(cloudKitManager)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didFinishLaunchingNotification)) { _ in
                    // Phase 4: Initialize iPhone Sync Client
                    registerBackgroundTasks()
                    
                    // Initialize CloudKit subscriptions and perform initial sync
                    Task {
                        try? await cloudKitManager.subscribeToChanges()
                        print("📱 [iPhone Sync Client] App launched - starting initial sync")
                    }
                }
        }
    }
    
    private func registerBackgroundTasks() {
        // This is handled in ClipboardService init, but we can add additional setup here if needed
        print("📱 [iOS] App launched - background tasks registered")
    }
}
