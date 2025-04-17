import SwiftUI
import AppKit
import UniformTypeIdentifiers

class StatusItemManager: NSObject {
    private var statusItem: NSStatusItem?
    private var statusBarButton: NSStatusBarButton?
    private var onFileDrop: ((URL) -> Void)?
    private var popover: NSPopover?
    private var eventMonitor: EventMonitor?
    
    // Create and configure the status item
    func setupStatusItem(onFileDrop: @escaping (URL) -> Void) {
        self.onFileDrop = onFileDrop
        
        // Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusBarButton = statusItem?.button
        
        // Set the status item image
        let statusBarImage = NSImage(systemSymbolName: "arrow.up.to.line", accessibilityDescription: "FFTPU")
        statusBarImage?.isTemplate = true  // Makes it adapt to system appearance
        statusBarButton?.image = statusBarImage
        
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
    }
    
    // Set the popover to show when the status item is clicked
    func setPopover(_ popover: NSPopover) {
        self.popover = popover
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