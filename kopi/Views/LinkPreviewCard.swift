//
//  LinkPreviewCard.swift
//  kopi
//
//  Created by Wan Menzy on 20/06/2025.
//

import SwiftUI
import AppKit

// MARK: - Link Preview Data Model

struct LinkPreviewData {
    let title: String?
    let description: String?
    let imageURL: String?
    let siteName: String?
    let url: String
}

// MARK: - Link Preview Card Component for macOS

struct LinkPreviewCard: View {
    let url: String
    let isCompact: Bool
    @State private var previewData: LinkPreviewData?
    @State private var isLoading = true
    
    init(url: String, isCompact: Bool = true) {
        self.url = url
        self.isCompact = isCompact
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 12) {
            if isLoading {
                // Loading state
                RoundedRectangle(cornerRadius: isCompact ? 6 : 8)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        VStack(spacing: isCompact ? 6 : 12) {
                            ProgressView()
                                .scaleEffect(isCompact ? 0.7 : 1.0)
                                .controlSize(isCompact ? .small : .regular)
                            Text("Loading preview...")
                                .font(isCompact ? .caption2 : .body)
                                .foregroundColor(.secondary)
                        }
                    )
            } else if let preview = previewData {
                // Preview content
                VStack(alignment: .leading, spacing: isCompact ? 6 : 12) {
                    // Thumbnail
                    AsyncImage(url: URL(string: preview.imageURL ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: isCompact ? 4 : 8)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.secondary)
                                    .font(isCompact ? .caption2 : .title2)
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: isCompact ? 60 : 180)
                    .clipShape(RoundedRectangle(cornerRadius: isCompact ? 4 : 8))
                    
                    // Content
                    VStack(alignment: .leading, spacing: isCompact ? 2 : 8) {
                        Text(preview.title ?? "Link")
                            .font(isCompact ? .caption : .headline)
                            .fontWeight(isCompact ? .medium : .semibold)
                            .lineLimit(isCompact ? 2 : 3)
                        
                        if let description = preview.description {
                            Text(description)
                                .font(isCompact ? .caption2 : .body)
                                .foregroundColor(.secondary)
                                .lineLimit(isCompact ? 2 : 4)
                        }
                        
                        if isCompact {
                            Text(URL(string: url)?.host ?? url)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        } else {
                            HStack {
                                if let siteName = preview.siteName {
                                    Text(siteName)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Text(URL(string: url)?.host ?? url)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                // Error state - fallback to simple URL display
                VStack(alignment: .leading, spacing: isCompact ? 4 : 12) {
                    HStack {
                        Image(systemName: "link")
                            .foregroundColor(.blue)
                            .font(isCompact ? .caption2 : .title2)
                        Text(isCompact ? "Link" : "Link Preview")
                            .font(isCompact ? .caption : .headline)
                            .fontWeight(isCompact ? .medium : .semibold)
                    }
                    
                    if !isCompact {
                        Text("Unable to load preview for this URL")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(URL(string: url)?.host ?? url)
                        .font(isCompact ? .caption2 : .caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear {
            fetchLinkPreview()
        }
    }
    
    private func fetchLinkPreview() {
        guard let url = URL(string: url) else {
            isLoading = false
            return
        }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let html = String(data: data, encoding: .utf8) ?? ""
                let preview = parseLinkPreview(from: html, url: self.url)
                
                await MainActor.run {
                    self.previewData = preview
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func parseLinkPreview(from html: String, url: String) -> LinkPreviewData {
        // Simple HTML parsing for Open Graph tags
        var title: String?
        var description: String?
        var imageURL: String?
        var siteName: String?
        
        // Extract title
        if let titleRange = html.range(of: "<title[^>]*>([^<]+)</title>", options: .regularExpression) {
            let titleMatch = String(html[titleRange])
            title = titleMatch.replacingOccurrences(of: #"<title[^>]*>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "</title>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Extract Open Graph title (preferred)
        if let ogTitleRange = html.range(of: #"<meta[^>]*property=["\']og:title["\'][^>]*content=["\']([^"\']*)["\']"#, options: .regularExpression) {
            let match = String(html[ogTitleRange])
            if let contentRange = match.range(of: #"content=["\']([^"\']*)["\']"#, options: .regularExpression) {
                let contentMatch = String(match[contentRange])
                title = contentMatch.replacingOccurrences(of: #"content=["\']"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"["\']$"#, with: "", options: .regularExpression)
            }
        }
        
        // Extract Open Graph description
        if let ogDescRange = html.range(of: #"<meta[^>]*property=["\']og:description["\'][^>]*content=["\']([^"\']*)["\']"#, options: .regularExpression) {
            let match = String(html[ogDescRange])
            if let contentRange = match.range(of: #"content=["\']([^"\']*)["\']"#, options: .regularExpression) {
                let contentMatch = String(match[contentRange])
                description = contentMatch.replacingOccurrences(of: #"content=["\']"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"["\']$"#, with: "", options: .regularExpression)
            }
        }
        
        // Extract Open Graph image
        if let ogImageRange = html.range(of: #"<meta[^>]*property=["\']og:image["\'][^>]*content=["\']([^"\']*)["\']"#, options: .regularExpression) {
            let match = String(html[ogImageRange])
            if let contentRange = match.range(of: #"content=["\']([^"\']*)["\']"#, options: .regularExpression) {
                let contentMatch = String(match[contentRange])
                imageURL = contentMatch.replacingOccurrences(of: #"content=["\']"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"["\']$"#, with: "", options: .regularExpression)
            }
        }
        
        // Extract site name
        if let ogSiteRange = html.range(of: #"<meta[^>]*property=["\']og:site_name["\'][^>]*content=["\']([^"\']*)["\']"#, options: .regularExpression) {
            let match = String(html[ogSiteRange])
            if let contentRange = match.range(of: #"content=["\']([^"\']*)["\']"#, options: .regularExpression) {
                let contentMatch = String(match[contentRange])
                siteName = contentMatch.replacingOccurrences(of: #"content=["\']"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"["\']$"#, with: "", options: .regularExpression)
            }
        }
        
        return LinkPreviewData(
            title: title,
            description: description,
            imageURL: imageURL,
            siteName: siteName,
            url: url
        )
    }
} 