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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
