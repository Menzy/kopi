//
//  MenuBarManager.swift
//  kopi
//
//  Created by Wan Menzy on 25/01/2025.
//

import SwiftUI
import AppKit

class MenuBarManager: NSObject, ObservableObject {
    static let shared = MenuBarManager()
    
    private var statusItem: NSStatusItem?
    private var pinboardWindow: NSWindow?
    private var mainWindow: NSWindow?
    
    @Published var isPinboardVisible = false
    @Published var isMainWindowVisible = false
    
    override init() {
        super.init()
        setupMenuBar()
        
        // Hide dock icon after menu bar is set up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    private func setupMenuBar() {
        // Ensure we're on the main thread
        DispatchQueue.main.async {
            // Create status item
            self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            
            guard let statusItem = self.statusItem else { return }
            
            // Set up the button
            if let button = statusItem.button {
                // Use kopiMenu icon
                button.image = NSImage(named: "kopiMenu")
                button.action = #selector(self.handleButtonClick)
                button.target = self
                button.toolTip = "Show Kopi Clipboard"
                
                // Enable right-click detection
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
        }
    }
    
    @objc private func handleButtonClick() {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            // Right click - show context menu
            showContextMenu()
        } else {
            // Left click - toggle pinboard
            togglePinboard()
        }
    }
    
    private func showContextMenu() {
        guard let statusItem = statusItem, let button = statusItem.button else { return }
        
        let menu = NSMenu()
        
        // Show/Hide Pinboard option
        let pinboardItem = NSMenuItem(
            title: isPinboardVisible ? "Hide Pinboard" : "Show Pinboard", 
            action: #selector(togglePinboard), 
            keyEquivalent: ""
        )
        pinboardItem.target = self
        menu.addItem(pinboardItem)
        
        // Show Main Window option
        let mainWindowItem = NSMenuItem(
            title: "Show Main Window", 
            action: #selector(showMainWindow), 
            keyEquivalent: "m"
        )
        mainWindowItem.target = self
        menu.addItem(mainWindowItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit option
        let quitItem = NSMenuItem(title: "Quit Kopi", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        // Show menu at button location
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }
    
    @objc private func togglePinboard() {
        if isPinboardVisible {
            hidePinboard()
        } else {
            showPinboard()
        }
    }
    
    @objc private func showMainWindow() {
        // Hide pinboard if visible
        if isPinboardVisible {
            hidePinboard()
        }
        
        // Check if main window already exists and is visible
        if let window = mainWindow, window.isVisible {
            // Just bring it to front
            NSApp.setActivationPolicy(.regular)
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // Reset to normal level after showing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                window.level = .normal
            }
            return
        }
        
        // Create main window if it doesn't exist
        Task { @MainActor in
            self.createAndShowMainWindow()
        }
    }
    
    @MainActor private func createAndShowMainWindow() {
        // Close existing main window if any
        if let existingWindow = mainWindow {
            existingWindow.close()
            mainWindow = nil
        }
        
        // Create the main window with proper setup
        let contentView = ContentView()
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
            .environmentObject(ClipboardMonitor.shared)
            .environmentObject(CloudKitManager.shared)
            .environmentObject(self)
        
        // Create the window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // Configure window
        window.title = "Kopi"
        window.center()
        window.isReleasedWhenClosed = false // Important: don't release when closed
        window.delegate = self
        
        // Create hosting view and set it
        let hostingView = NSHostingView(rootView: contentView)
        window.contentView = hostingView
        
        // Store reference
        mainWindow = window
        
        // Change activation policy to show window properly
        NSApp.setActivationPolicy(.regular)
        
        // Set window level to floating temporarily to ensure it appears on top
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Reset to normal level after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            window.level = .normal
        }
        
        isMainWindowVisible = true
    }
    
    @objc private func showPinboard() {
        guard let statusItem = statusItem, let button = statusItem.button else { return }
        
        // Get button frame in screen coordinates
        let buttonFrame = button.convert(button.bounds, to: nil)
        guard let buttonWindow = button.window else { return }
        let screenFrame = buttonWindow.convertToScreen(buttonFrame)
        
        // Create pinboard window if needed
        if pinboardWindow == nil {
            createPinboardWindow()
        }
        
        guard let window = pinboardWindow else { return }
        
        // Position window below the menu bar button - full screen width
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenRect = screen.visibleFrame
        let windowSize = NSSize(width: screenRect.width, height: 200)
        let windowOrigin = NSPoint(
            x: screenRect.minX,
            y: screenFrame.minY - windowSize.height - 5
        )
        
        window.setFrame(NSRect(origin: windowOrigin, size: windowSize), display: true)
        window.makeKeyAndOrderFront(nil)
        
        isPinboardVisible = true
    }
    
    @objc private func hidePinboard() {
        pinboardWindow?.orderOut(nil)
        isPinboardVisible = false
    }
    
    private func createPinboardWindow() {
        // Get screen dimensions for full-width window
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenRect = screen.visibleFrame
        
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: screenRect.width, height: 200),
            styleMask: [.nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // Configure window properties
        window.level = .floating
        window.backgroundColor = NSColor.clear
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Create and set the content view
        let hostingView = NSHostingView(rootView: HorizontalPinboardView(onDismiss: {
            self.hidePinboard()
        })
        .environmentObject(ClipboardMonitor.shared))
        
        window.contentView = hostingView
        
        // Set up window delegate to handle events
        window.delegate = self
        
        pinboardWindow = window
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    deinit {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }
}

// MARK: - NSWindowDelegate

extension MenuBarManager: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        // Hide pinboard when it loses focus
        if notification.object as? NSWindow == pinboardWindow {
            hidePinboard()
        }
    }
    
    func windowWillClose(_ notification: Notification) {
        // Handle main window closing
        if notification.object as? NSWindow == mainWindow {
            isMainWindowVisible = false
            mainWindow = nil
            // Return to accessory mode when main window closes
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Allow window to close but don't quit the app
        if sender == mainWindow {
            // Just hide the window, don't quit the app
            return true
        }
        return true
    }
}