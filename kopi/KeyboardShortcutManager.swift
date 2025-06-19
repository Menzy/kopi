//
//  KeyboardShortcutManager.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import Foundation
import Carbon
import AppKit

class KeyboardShortcutManager: ObservableObject {
    static let shared = KeyboardShortcutManager()
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    
    // Default shortcut: Cmd+Shift+V
    @Published var currentShortcut = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(cmdKey | shiftKey)
    )
    
    var onShortcutPressed: (() -> Void)?
    
    private init() {}
    
    func registerGlobalShortcut() {
        // Unregister existing shortcut first
        unregisterGlobalShortcut()
        
        // Create event type
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        
        // Install event handler
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, event, userData) -> OSStatus in
                guard let userData = userData, let event = event else { return noErr }
                let manager = Unmanaged<KeyboardShortcutManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handleHotKeyEvent(event: event)
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )
        
        guard status == noErr else {
            print("❌ Failed to install event handler: \(status)")
            return
        }
        
        // Register hot key
        let hotKeyID = EventHotKeyID(signature: OSType(fourCharCode("kopi")), id: 1)
        
        let registerStatus = RegisterEventHotKey(
            currentShortcut.keyCode,
            currentShortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if registerStatus == noErr {
            print("✅ Global keyboard shortcut registered: \(currentShortcut.displayString)")
        } else {
            print("❌ Failed to register global shortcut: \(registerStatus)")
        }
    }
    
    func unregisterGlobalShortcut() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
    
    func updateShortcut(keyCode: UInt32, modifiers: UInt32) {
        currentShortcut = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
        registerGlobalShortcut()
    }
    
    private func handleHotKeyEvent(event: EventRef) {
        print("🔥 Global shortcut pressed!")
        
        DispatchQueue.main.async {
            self.onShortcutPressed?()
        }
    }
    
    // Helper function to convert FourCC to OSType
    private func fourCharCode(_ code: String) -> FourCharCode {
        assert(code.count == 4)
        var result: FourCharCode = 0
        for char in code.utf8 {
            result = (result << 8) + FourCharCode(char)
        }
        return result
    }
}

// MARK: - Keyboard Shortcut Model

struct KeyboardShortcut {
    let keyCode: UInt32
    let modifiers: UInt32
    
    var displayString: String {
        var components: [String] = []
        
        if modifiers & UInt32(controlKey) != 0 {
            components.append("⌃")
        }
        if modifiers & UInt32(optionKey) != 0 {
            components.append("⌥")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            components.append("⇧")
        }
        if modifiers & UInt32(cmdKey) != 0 {
            components.append("⌘")
        }
        
        components.append(keyCodeToString(keyCode))
        
        return components.joined()
    }
    
    private func keyCodeToString(_ keyCode: UInt32) -> String {
        switch keyCode {
        case UInt32(kVK_ANSI_A): return "A"
        case UInt32(kVK_ANSI_B): return "B"
        case UInt32(kVK_ANSI_C): return "C"
        case UInt32(kVK_ANSI_D): return "D"
        case UInt32(kVK_ANSI_E): return "E"
        case UInt32(kVK_ANSI_F): return "F"
        case UInt32(kVK_ANSI_G): return "G"
        case UInt32(kVK_ANSI_H): return "H"
        case UInt32(kVK_ANSI_I): return "I"
        case UInt32(kVK_ANSI_J): return "J"
        case UInt32(kVK_ANSI_K): return "K"
        case UInt32(kVK_ANSI_L): return "L"
        case UInt32(kVK_ANSI_M): return "M"
        case UInt32(kVK_ANSI_N): return "N"
        case UInt32(kVK_ANSI_O): return "O"
        case UInt32(kVK_ANSI_P): return "P"
        case UInt32(kVK_ANSI_Q): return "Q"
        case UInt32(kVK_ANSI_R): return "R"
        case UInt32(kVK_ANSI_S): return "S"
        case UInt32(kVK_ANSI_T): return "T"
        case UInt32(kVK_ANSI_U): return "U"
        case UInt32(kVK_ANSI_V): return "V"
        case UInt32(kVK_ANSI_W): return "W"
        case UInt32(kVK_ANSI_X): return "X"
        case UInt32(kVK_ANSI_Y): return "Y"
        case UInt32(kVK_ANSI_Z): return "Z"
        case UInt32(kVK_Space): return "Space"
        case UInt32(kVK_Return): return "Return"
        case UInt32(kVK_Tab): return "Tab"
        case UInt32(kVK_Escape): return "Escape"
        default: return "Key\(keyCode)"
        }
    }
}

// MARK: - Quick Paste Manager

class QuickPasteManager: ObservableObject {
    static let shared = QuickPasteManager()
    
    private let keyboardManager = KeyboardShortcutManager.shared
    private let dataManager = ClipboardDataManager.shared
    
    @Published var isQuickPasteVisible = false
    @Published var quickPasteItems: [ClipboardItem] = []
    
    private init() {
        keyboardManager.onShortcutPressed = { [weak self] in
            self?.showQuickPaste()
        }
    }
    
    func showQuickPaste() {
        // Get recent clipboard items (up to 10)
        quickPasteItems = dataManager.getRecentItems(limit: 10)
        isQuickPasteVisible = true
        
        // Auto-hide after 10 seconds if no interaction
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if self.isQuickPasteVisible {
                self.hideQuickPaste()
            }
        }
    }
    
    func hideQuickPaste() {
        isQuickPasteVisible = false
    }
    
    func selectItem(at index: Int) {
        guard index < quickPasteItems.count else { return }
        let item = quickPasteItems[index]
        
        if let content = item.content {
            // Copy to pasteboard
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(content, forType: .string)
            
            print("📋 Quick pasted: \(content.prefix(50))...")
        }
        
        hideQuickPaste()
    }
} 