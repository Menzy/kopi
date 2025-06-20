//
//  ContentType.swift
//  kopi iOS
//
//  Created by Wan Menzy on 20/06/2025.
//

import Foundation
import SwiftUI

enum ContentType: String, CaseIterable {
    case text = "text"
    case url = "url"
    case image = "image"
    
    var displayName: String {
        switch self {
        case .text:
            return "Text"
        case .url:
            return "URL"
        case .image:
            return "Image"
        }
    }
    
    var systemImage: String {
        switch self {
        case .text:
            return "doc.text"
        case .url:
            return "link"
        case .image:
            return "photo"
        }
    }
    
    var color: Color {
        switch self {
        case .text:
            return .blue
        case .url:
            return .green
        case .image:
            return .purple
        }
    }
} 
