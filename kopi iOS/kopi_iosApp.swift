//
//  kopi_iosApp.swift
//  kopi ios
//
//  Created by Wan Menzy on 20/06/2025.
//

import SwiftUI

@main
struct kopi_iosApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var clipboardService = ClipboardService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(clipboardService)
        }
    }
}
