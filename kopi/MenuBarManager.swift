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
    
    @Published var isPinboardVisible = false
    
    override init() {
        super.init()
        setupMenuBar()
    }
    
    private func setupMenuBar() {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        guard let statusItem = statusItem else { return }
        
        // Set up the button
        if let button = statusItem.button {
            // Use clipboard icon
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clipboard")
            button.action = #selector(handleButtonClick)
            button.target = self
            button.toolTip = "Show Kopi Clipboard"
            
            // Enable right-click detection
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Create menu for right-click (but don't assign it yet)
        createContextMenu()
    }
    
    private func createContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Pinboard", action: #selector(showPinboard), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Kopi", action: #selector(quitApp), keyEquivalent: "q"))
        
        // Don't assign the menu to statusItem.menu - we'll show it manually
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
        let showItem = NSMenuItem(title: isPinboardVisible ? "Hide Pinboard" : "Show Pinboard", 
                                 action: #selector(togglePinboard), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        menu.addItem(NSMenuItem.separator())
        
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
        let windowSize = NSSize(width: screenRect.width, height: 200) // Further increased height
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
        }))
        
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
} 