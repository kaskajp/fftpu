//
//  FFTPUApp.swift
//  FFTPU
//
//  Created by Jonas on 2025-04-17.
//

import SwiftUI
import SwiftData
import AppKit

@main
struct FFTPUApp: App {
    @StateObject private var appState = AppState()
    
    let sharedModelContainer: ModelContainer
    
    // Settings window manager - initialized in init
    private let settingsManager: SettingsWindowManager
    
    init() {
        // Initialize the model container first
        let schema = Schema([
            UploadedFile.self,
            FTPSettings.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            self.sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        
        // Create a temporary AppState for initialization
        // We can't access @StateObject directly in init
        let tempAppState = AppState()
        
        // Now create settings manager with the container and temporary appState
        self.settingsManager = SettingsWindowManager(
            appState: tempAppState, 
            sharedModelContainer: sharedModelContainer
        )
    }
    
    var body: some Scene {
        // Menu Bar Extra
        MenuBarExtra("FFTPU", systemImage: "arrow.up.to.line") {
            MenuBarView(openSettings: { 
                // Update the settings manager with the current appState
                settingsManager.updateAppState(appState)
                settingsManager.showSettingsWindow()
            })
            .environmentObject(appState)
            .modelContainer(sharedModelContainer)
        }
        .menuBarExtraStyle(.window)
    }
}

// Main app state
class AppState: ObservableObject {
    @Published var isShowingDropZone = false
    @Published var isShowingSettings = false
    @Published var currentUpload: UploadedFile?
    @Published var recentUploads: [UploadedFile] = []
}
