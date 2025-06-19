//
//  SidebarView.swift
//  kopi
//
//  Created by Wan Menzy on 19/06/2025.
//

import SwiftUI
import AppKit

struct SidebarView: View {
    @Binding var selectedFilter: SidebarFilter
    let availableApps: [AppInfo]
    let totalItemCount: Int
    let contentTypeCounts: [ContentType: Int]
    
    var body: some View {
        List(selection: $selectedFilter) {
            // All Items Section
            Section {
                SidebarItemView(
                    filter: .all,
                    icon: "doc.on.clipboard",
                    title: "All",
                    count: totalItemCount,
                    isSelected: selectedFilter == .all
                )
                .tag(SidebarFilter.all)
            }
            
            // Types Section
            Section("Types") {
                ForEach(ContentType.allCases, id: \.self) { contentType in
                    let count = contentTypeCounts[contentType] ?? 0
                    if count > 0 {
                        SidebarItemView(
                            filter: .contentType(contentType),
                            icon: contentType.systemImage,
                            title: contentType.displayName,
                            count: count,
                            isSelected: selectedFilter == .contentType(contentType)
                        )
                        .tag(SidebarFilter.contentType(contentType))
                    }
                }
            }
            
            // Collections Section
            Section("Collections") {
                ForEach(availableApps, id: \.bundleID) { app in
                    SidebarItemView(
                        filter: .app(app.bundleID),
                        icon: nil,
                        title: app.name,
                        count: app.itemCount,
                        isSelected: selectedFilter == .app(app.bundleID),
                        appIcon: app.iconData
                    )
                    .tag(SidebarFilter.app(app.bundleID))
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .navigationTitle("Kopi")
    }
}

// MARK: - Sidebar Item View

struct SidebarItemView: View {
    let filter: SidebarFilter
    let icon: String?
    let title: String
    let count: Int
    let isSelected: Bool
    let appIcon: Data?
    
    init(filter: SidebarFilter, icon: String?, title: String, count: Int, isSelected: Bool, appIcon: Data? = nil) {
        self.filter = filter
        self.icon = icon
        self.title = title
        self.count = count
        self.isSelected = isSelected
        self.appIcon = appIcon
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Group {
                if let appIcon = appIcon, let nsImage = NSImage(data: appIcon) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if let systemIcon = icon {
                    Image(systemName: systemIcon)
                        .foregroundColor(.accentColor)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "app.fill")
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                }
            }
            
            // Title
            Text(title)
                .font(.body)
                .lineLimit(1)
            
            Spacer()
            
            // Count badge
            if count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.quaternaryLabelColor))
                    )
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - Sidebar Filter

enum SidebarFilter: Hashable, Equatable {
    case all
    case contentType(ContentType)
    case app(String) // Bundle ID
    
    static func == (lhs: SidebarFilter, rhs: SidebarFilter) -> Bool {
        switch (lhs, rhs) {
        case (.all, .all):
            return true
        case (.contentType(let lhsType), .contentType(let rhsType)):
            return lhsType == rhsType
        case (.app(let lhsBundle), .app(let rhsBundle)):
            return lhsBundle == rhsBundle
        default:
            return false
        }
    }
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case .all:
            hasher.combine("all")
        case .contentType(let contentType):
            hasher.combine("contentType")
            hasher.combine(contentType)
        case .app(let bundleID):
            hasher.combine("app")
            hasher.combine(bundleID)
        }
    }
}

// MARK: - App Info Model

struct AppInfo {
    let bundleID: String
    let name: String
    let iconData: Data?
    let itemCount: Int
    
    init(bundleID: String, name: String, iconData: Data? = nil, itemCount: Int = 0) {
        self.bundleID = bundleID
        self.name = name
        self.iconData = iconData
        self.itemCount = itemCount
    }
} 