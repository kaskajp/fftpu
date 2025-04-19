import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

class StatusItemManager: NSObject {
    private var statusItem: NSStatusItem?
    private var statusBarButton: NSStatusBarButton?
    private var onFileDrop: ((URL) -> Void)?
    private var popover: NSPopover?
    private var eventMonitor: EventMonitor?
    private var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private var animationTimer: Timer?
    private var uploadingFilename: String?
    private var animationDisplayLink: CVDisplayLink?
    private var animationStartTime: Date = Date()
    
    deinit {
        stopIconAnimation()
        if let displayLink = animationDisplayLink {
            CVDisplayLinkStop(displayLink)
        }
    }
    
    // Create and configure the status item
    func setupStatusItem(onFileDrop: @escaping (URL) -> Void) {
        self.onFileDrop = onFileDrop
        
        // Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusBarButton = statusItem?.button
        
        // Set the status item image
        updateStatusBarIcon(isLoading: false)
        
        // Register for drag and drop
        let dragTypes = [UTType.fileURL.identifier]
        statusBarButton?.registerForDraggedTypes(dragTypes.map { NSPasteboard.PasteboardType($0) })
        
        // Set self as the drag delegate
        statusBarButton?.wantsLayer = true
        statusBarButton?.target = self
        statusBarButton?.action = #selector(statusBarButtonClicked)
        
        // Make the button handle drag operations
        if let field = statusBarButton, let dropHandler = self.onFileDrop {
            let dragView = StatusItemDragView(frame: field.bounds, dropHandler: dropHandler)
            dragView.autoresizingMask = [.width, .height]
            field.addSubview(dragView)
        }
        
        // Create event monitor to detect clicks outside the popover
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let popover = self?.popover, popover.isShown {
                popover.close()
            }
        }
        
        // Setup more efficient animation using display link if possible
        setupDisplayLink()
    }
    
    private func setupDisplayLink() {
        // Set up CVDisplayLink for smoother animation
        var displayLink: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        
        if let displayLink = displayLink {
            let opaqueself = Unmanaged.passUnretained(self).toOpaque()
            
            CVDisplayLinkSetOutputCallback(displayLink, { (displayLink, inNow, inOutputTime, flagsIn, flagsOut, userData) -> CVReturn in
                let mySelf = Unmanaged<StatusItemManager>.fromOpaque(userData!).takeUnretainedValue()
                
                // Dispatch to main thread for UI updates
                DispatchQueue.main.async {
                    if mySelf.appState?.currentUpload != nil {
                        mySelf.updateAnimationFrame()
                    }
                }
                
                return kCVReturnSuccess
            }, opaqueself)
            
            animationDisplayLink = displayLink
        }
    }
    
    // Set the popover to show when the status item is clicked
    func setPopover(_ popover: NSPopover) {
        self.popover = popover
    }
    
    // Set the app state and observe for changes
    func setAppState(_ appState: AppState) {
        self.appState = appState
        
        // Observe current upload state changes
        appState.$currentUpload
            .receive(on: RunLoop.main)
            .sink { [weak self] upload in
                self?.uploadingFilename = upload?.filename
                self?.updateStatusBarIcon(isLoading: upload != nil)
                if upload != nil {
                    self?.startIconAnimation()
                } else {
                    self?.stopIconAnimation()
                }
            }
            .store(in: &cancellables)
        
        // Observe upload status changes for tooltip
        appState.$uploadStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard !status.isEmpty else { return }
                self?.statusBarButton?.toolTip = status
            }
            .store(in: &cancellables)
    }
    
    private func startIconAnimation() {
        // Stop any existing animation
        stopIconAnimation()
        
        animationStartTime = Date()
        
        // Start the display link if available
        if let displayLink = animationDisplayLink {
            CVDisplayLinkStart(displayLink)
        } else {
            // Fallback to timer-based animation
            animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                self?.updateAnimationFrame()
            }
        }
    }
    
    private func stopIconAnimation() {
        // Stop timer-based animation
        animationTimer?.invalidate()
        animationTimer = nil
        
        // Stop display link animation
        if let displayLink = animationDisplayLink {
            CVDisplayLinkStop(displayLink)
        }
        
        // Reset to static icon
        if appState?.currentUpload == nil {
            statusBarButton?.image = createConsistentSizeIcon(named: "arrow.up.to.line")
        }
    }
    
    private func updateAnimationFrame() {
        // Time-based animation rather than frame counting for smoother results
        let elapsed = Date().timeIntervalSince(animationStartTime)
        let animationCycleDuration = 1.2 // seconds for a complete cycle
        
        // Calculate phase (0.0 to 1.0) in the animation cycle
        let phase = (elapsed.truncatingRemainder(dividingBy: animationCycleDuration)) / animationCycleDuration
        
        // Choose icon based on phase - only using the first 3 icons
        let iconName: String
        
        if phase < 0.33 {
            iconName = "arrow.up"
        } else if phase < 0.66 {
            iconName = "arrow.up.to.line.compact"
        } else {
            iconName = "arrow.up.to.line"
        }
        
        // Apply the prepared image on the appropriate thread
        if Thread.isMainThread {
            statusBarButton?.image = createConsistentSizeIcon(named: iconName)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.statusBarButton?.image = self?.createConsistentSizeIcon(named: iconName)
            }
        }
    }
    
    // Helper function to create consistently sized status bar icons
    private func createConsistentSizeIcon(named iconName: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "FFTPU") else {
            return nil
        }
        
        image.isTemplate = true
        
        // Create a consistent-sized image to prevent jumping
        let finalSize = NSSize(width: 18, height: 18)
        let resizedImage = NSImage(size: finalSize)
        
        resizedImage.lockFocus()
        
        // Calculate centering offsets
        let xOffset = (finalSize.width - image.size.width) / 2
        let yOffset = (finalSize.height - image.size.height) / 2
        
        // Draw with consistent vertical alignment
        image.draw(in: NSRect(
            x: max(0, xOffset),
            y: max(0, yOffset),
            width: min(image.size.width, finalSize.width),
            height: min(image.size.height, finalSize.height)
        ))
        
        resizedImage.unlockFocus()
        resizedImage.isTemplate = true
        
        return resizedImage
    }
    
    // Update the status bar icon based on loading state
    private func updateStatusBarIcon(isLoading: Bool) {
        if isLoading {
            // Set tooltip with upload status
            if let filename = uploadingFilename {
                statusBarButton?.toolTip = "Uploading: \(filename)"
            } else {
                statusBarButton?.toolTip = "Uploading file..."
            }
            
            // Initial animation frame
            statusBarButton?.image = createConsistentSizeIcon(named: "arrow.up")
            
            // Animation is handled by timer in startIconAnimation()
        } else {
            // Clear tooltip when not uploading
            statusBarButton?.toolTip = nil
            
            // Reset to static icon
            statusBarButton?.image = createConsistentSizeIcon(named: "arrow.up.to.line")
        }
    }
    
    // Toggle the popover when the status bar is clicked
    @objc private func statusBarButtonClicked() {
        guard let popover = popover, let button = statusBarButton else { return }
        
        if popover.isShown {
            popover.close()
            eventMonitor?.stop()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            eventMonitor?.start()
        }
    }
}

// Custom view to handle drag operations
class StatusItemDragView: NSView {
    private var dropHandler: (URL) -> Void
    
    init(frame frameRect: NSRect, dropHandler: @escaping (URL) -> Void) {
        self.dropHandler = dropHandler
        super.init(frame: frameRect)
        
        // Register for drag types
        registerForDraggedTypes([NSPasteboard.PasteboardType(UTType.fileURL.identifier)])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // Show that we can accept the drop
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Change appearance to indicate drop target
        if let button = superview as? NSStatusBarButton {
            button.highlight(true)
        }
        return .copy
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        // Restore normal appearance
        if let button = superview as? NSStatusBarButton {
            button.highlight(false)
        }
    }
    
    // Handle the dropped file
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        
        if let fileURL = pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL {
            // Reset highlight
            if let button = superview as? NSStatusBarButton {
                button.highlight(false)
            }
            
            // Handle the file
            dropHandler(fileURL)
            return true
        }
        
        return false
    }
}

// Helper class to monitor mouse events outside the popover
class EventMonitor {
    private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent?) -> Void
    
    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }
    
    deinit {
        stop()
    }
    
    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }
    
    func stop() {
        if monitor != nil {
            NSEvent.removeMonitor(monitor!)
            monitor = nil
        }
    }
} 