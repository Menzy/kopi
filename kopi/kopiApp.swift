//
//  kopiApp.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import SwiftUI

@main
struct kopiApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var clipboardMonitor = ClipboardMonitor.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(clipboardMonitor)
                .onAppear {
                    // Start clipboard monitoring when app appears
                    clipboardMonitor.startMonitoring()
                }
                .onDisappear {
                    // Stop monitoring when app disappears
                    clipboardMonitor.stopMonitoring()
                }
        }
    }
}
