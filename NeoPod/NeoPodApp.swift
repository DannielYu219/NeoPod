//
//  NeoPodApp.swift
//  NeoPod
//
//  Created by Danniel Yu on 2/14/R8.
//

import SwiftUI
import CoreData

@main
struct NeoPodApp: App {
    let persistenceController = PersistenceController.shared
    
    init() {
        FileSystemManager.ensureAppFoldersExist()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
