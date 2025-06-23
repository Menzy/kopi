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
    case image = "image"
    case url = "url"
    case file = "file"
    
    var displayName: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .url: return "Link"
        case .file: return "File"
        }
    }
    
    var systemImageName: String {
        switch self {
        case .text: return "doc.text"
        case .image: return "photo"
        case .url: return "link"
        case .file: return "doc"
        }
    }
    
    var color: Color {
        switch self {
        case .text:
            return .blue
        case .image:
            return .purple
        case .url:
            return .green
        case .file:
            return .gray
        }
    }
}

enum SyncStatus: String, CaseIterable {
    case local = "local"
    case syncing = "syncing"
    case synced = "synced"
    case failed = "failed"
    
    var displayName: String {
        switch self {
        case .local: return "Local"
        case .syncing: return "Syncing"
        case .synced: return "Synced"
        case .failed: return "Failed"
        }
    }
    
    var systemImageName: String {
        switch self {
        case .local: return "iphone"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .synced: return "checkmark.icloud"
        case .failed: return "exclamationmark.icloud"
        }
    }
} 