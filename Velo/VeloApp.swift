//
//  VeloApp.swift
//  Velo
//
//  Created by Fraser on 06/02/2026.
//

import SwiftUI
import CoreData

@main
struct VeloApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
