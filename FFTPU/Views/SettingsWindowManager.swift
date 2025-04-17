import SwiftUI
import SwiftData
import AppKit

class SettingsWindowManager: ObservableObject {
    private var settingsWindow: NSWindow?
    private var appState: AppState
    private var sharedModelContainer: ModelContainer
    
    init(appState: AppState, sharedModelContainer: ModelContainer) {
        self.appState = appState
        self.sharedModelContainer = sharedModelContainer
    }
    
    // Method to update the app state reference
    func updateAppState(_ newAppState: AppState) {
        self.appState = newAppState
        
        // If window exists, update its content view with new appState
        if let window = settingsWindow {
            let settingsView = SettingsView()
                .environmentObject(appState)
                .modelContainer(sharedModelContainer)
                .frame(width: 550, height: 450)
                .fixedSize()
            
            window.contentView = NSHostingView(rootView: settingsView)
        }
    }
    
    func showSettingsWindow() {
        // If window exists, show it
        if let window = settingsWindow {
            if window.isVisible {
                window.orderFrontRegardless()
            } else {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create a new window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 450),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        // Configure window
        window.title = "Settings"
        window.center()
        window.isReleasedWhenClosed = false
        
        // Set up the SwiftUI view as content
        let settingsView = SettingsView()
            .environmentObject(appState)
            .modelContainer(sharedModelContainer)
            .frame(width: 550, height: 450)
            .fixedSize()
        
        window.contentView = NSHostingView(rootView: settingsView)
        
        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Save reference
        self.settingsWindow = window
    }
} 