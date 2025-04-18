//
//  FFTPUApp.swift
//  FFTPU
//
//  Created by Jonas on 2025-04-17.
//

import SwiftUI
import SwiftData
import AppKit
import OSLog

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
        
        // Configure model
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        // Create the model container (with proper error handling)
        var container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // If container creation fails, try to recover by deleting the database
            print("Error creating model container: \(error)")
            print("Attempting to recover by deleting the database")
            
            // Delete the SwiftData store
            let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let storeURL = applicationSupportURL.appendingPathComponent("default.store")
            
            do {
                if FileManager.default.fileExists(atPath: storeURL.path) {
                    try FileManager.default.removeItem(at: storeURL)
                    print("Successfully deleted database at: \(storeURL.path)")
                }
                
                // Try creating container again
                do {
                    container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                } catch {
                    print("Final attempt failed: \(error)")
                    // Create an in-memory container as last resort
                    let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                    container = try! ModelContainer(for: schema, configurations: [inMemoryConfig])
                }
            } catch {
                print("Failed to delete database: \(error)")
                // Create an in-memory container as last resort
                let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = try! ModelContainer(for: schema, configurations: [inMemoryConfig])
            }
        }
        
        // Assign to self (guaranteed to be initialized now)
        self.sharedModelContainer = container
        
        // Create a temporary AppState for initialization
        let tempAppState = AppState()
        
        // Create settings manager
        self.settingsManager = SettingsWindowManager(
            appState: tempAppState, 
            sharedModelContainer: container
        )
        
        // Schedule the migration for after init is complete
        DispatchQueue.main.async {
            // Migration code inlined to avoid capturing self
            Task { @MainActor in
                // Manually migrate any existing FTPSettings to add the path if needed
                let context = container.mainContext
                let fetchDescriptor = FetchDescriptor<FTPSettings>()
                if let settings = try? context.fetch(fetchDescriptor) {
                    var didChange = false
                    for setting in settings {
                        // If we have an old version without path set, update it
                        if setting.ftpPath.isEmpty {
                            setting.ftpPath = "/"
                            didChange = true
                        }
                    }
                    if didChange {
                        try? context.save()
                    }
                }
            }
        }
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
        newPopover.contentSize = NSSize(width: 300, height: 300)
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
                let logger = Logger(subsystem: "com.FFTPU", category: "StatusItemDrop")
                logger.info("File dropped on status item: \(url.lastPathComponent)")
                
                // Create FTPService and upload file
                let modelContext = self.sharedModelContainer.mainContext
                
                // Query for FTPSettings
                let fetchDescriptor = FetchDescriptor<FTPSettings>()
                let ftpSettings = try? modelContext.fetch(fetchDescriptor)
                
                // Validate settings
                if ftpSettings?.isEmpty ?? true {
                    logger.error("No FTP settings found")
                    let alert = NSAlert()
                    alert.messageText = "No SFTP Settings"
                    alert.informativeText = "Please configure your SFTP settings before uploading a file."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    
                    // Open settings window
                    self.settingsManager.showSettingsWindow()
                    return
                }
                
                let settings = ftpSettings!.first!
                if settings.ftpServerURL.isEmpty || settings.ftpUsername.isEmpty || settings.ftpPassword.isEmpty {
                    logger.error("Incomplete SFTP settings")
                    let alert = NSAlert()
                    alert.messageText = "Incomplete SFTP Settings"
                    alert.informativeText = "Please complete your SFTP settings configuration before uploading."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    
                    // Open settings window
                    self.settingsManager.showSettingsWindow()
                    return
                }
                
                let ftpService = FTPService(settings: settings)
                
                // Create UploadedFile record
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                logger.debug("File size: \(fileSize) bytes")
                
                let uploadedFile = UploadedFile(
                    filename: url.lastPathComponent,
                    originalPath: url.path,
                    uploadSize: fileSize
                )
                
                // Insert into model context and update app state
                logger.debug("Inserting file record into model context")
                modelContext.insert(uploadedFile)
                self.appState.setCurrentUpload(uploadedFile)
                
                // Start upload
                Task { @MainActor in
                    do {
                        logger.debug("Starting FTP upload task")
                        let remoteURL = try await ftpService.uploadFile(localURL: url, uploadedFile: uploadedFile)
                        
                        logger.info("Upload completed successfully, remote URL: \(remoteURL)")
                        uploadedFile.remoteURL = remoteURL
                        uploadedFile.isUploading = false
                        uploadedFile.uploadProgress = 1.0
                        self.appState.setCurrentUpload(nil)
                        
                        // Save model context
                        try? modelContext.save()
                        
                        // Copy URL to clipboard automatically
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(remoteURL, forType: .string)
                    } catch {
                        logger.error("Upload failed with error: \(error.localizedDescription)")
                        uploadedFile.isUploading = false
                        uploadedFile.errorMessage = error.localizedDescription
                        self.appState.logUploadError(uploadedFile, error: error)
                        self.appState.setCurrentUpload(nil)
                        
                        // Save model context
                        try? modelContext.save()
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
    
    private let logger = Logger(subsystem: "com.FFTPU", category: "AppState")
    
    init() {
        logger.debug("AppState initialized")
    }
    
    func setCurrentUpload(_ upload: UploadedFile?) {
        if let upload = upload {
            logger.debug("Starting upload: \(upload.filename)")
            self.currentUpload = upload
        } else {
            if let previous = currentUpload {
                logger.debug("Upload completed or failed: \(previous.filename)")
            }
            self.currentUpload = nil
        }
    }
    
    func logUploadError(_ upload: UploadedFile, error: Error) {
        logger.error("Upload failed for \(upload.filename): \(error.localizedDescription)")
    }
}
