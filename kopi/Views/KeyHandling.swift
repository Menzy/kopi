//
//  KeyHandling.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import SwiftUI
import AppKit

// Extension to handle key events in SwiftUI
extension View {
    func onKeyDown(perform action: @escaping (NSEvent) -> Bool) -> some View {
        self.background(KeyEventHandlingView(onKeyDown: action))
    }
}

struct KeyEventHandlingView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyHandlingNSView()
        view.onKeyDown = onKeyDown
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class KeyHandlingNSView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if let handler = onKeyDown, handler(event) {
            return
        }
        super.keyDown(with: event)
    }
} 