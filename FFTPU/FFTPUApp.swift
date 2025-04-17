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
    
    // Status item manager for handling drag and drop on the menu bar
    private let statusItemManager = StatusItemManager()
    @State private var popover: NSPopover? = nil
    
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
        WindowGroup(id: "hidden") {
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear {
                    setupStatusItem()
                }
        }
        .defaultSize(width: 0, height: 0)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
    
    private func setupStatusItem() {
        // Create popover for the menu
        let newPopover = NSPopover()
        newPopover.contentSize = NSSize(width: 300, height: 400)
        newPopover.behavior = .transient
        
        // Set content view for the popover
        let menuView = MenuBarView(openSettings: { 
            // Update the settings manager with the current appState
            settingsManager.updateAppState(appState)
            settingsManager.showSettingsWindow()
        })
        .environmentObject(appState)
        .modelContainer(sharedModelContainer)
        
        newPopover.contentViewController = NSHostingController(rootView: menuView)
        self.popover = newPopover
        
        // Set up the status item with drag and drop handling
        statusItemManager.setupStatusItem { url in
            // This closure is called when a file is dropped on the status item
            DispatchQueue.main.async {
                // Create FTPService and upload file
                let modelContext = self.sharedModelContainer.mainContext
                
                // Query for FTPSettings
                let fetchDescriptor = FetchDescriptor<FTPSettings>()
                let ftpSettings = try? modelContext.fetch(fetchDescriptor)
                let ftpService = FTPService(settings: ftpSettings?.first ?? FTPSettings())
                
                // Create UploadedFile record
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                let uploadedFile = UploadedFile(
                    filename: url.lastPathComponent,
                    originalPath: url.path,
                    uploadSize: fileSize
                )
                
                // Insert into model context and update app state
                modelContext.insert(uploadedFile)
                self.appState.currentUpload = uploadedFile
                
                // Start upload
                Task { @MainActor in
                    do {
                        let remoteURL = try await ftpService.uploadFile(localURL: url, uploadedFile: uploadedFile)
                        
                        uploadedFile.remoteURL = remoteURL
                        uploadedFile.isUploading = false
                        uploadedFile.uploadProgress = 1.0
                        self.appState.currentUpload = nil
                        
                        // Copy URL to clipboard automatically
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(remoteURL, forType: .string)
                    } catch {
                        uploadedFile.isUploading = false
                        uploadedFile.errorMessage = error.localizedDescription
                        self.appState.currentUpload = nil
                    }
                }
            }
        }
        
        // Set the popover to the status item manager
        if let popover = self.popover {
            statusItemManager.setPopover(popover)
        }
    }
}

// Main app state
class AppState: ObservableObject {
    @Published var isShowingDropZone = false
    @Published var isShowingSettings = false
    @Published var currentUpload: UploadedFile?
    @Published var recentUploads: [UploadedFile] = []
}
