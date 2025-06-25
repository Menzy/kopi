//
//  LinkPreviewCard.swift
//  kopi
//
//  Created by Wan Menzy on 20/06/2025.
//

import SwiftUI
import AppKit
import LinkPresentation

// MARK: - Link Preview Data Model

struct LinkPreviewData {
    let title: String?
    let description: String?
    let imageURL: String?
    let siteName: String?
    let url: String
    var image: NSImage?
}

// MARK: - Link Preview Card Component for macOS

struct LinkPreviewCard: View {
    let url: String
    let isCompact: Bool
    let isExtraCompact: Bool
    @State private var previewData: LinkPreviewData?
    @State private var isLoading = true
    
    init(url: String, isCompact: Bool = true, isExtraCompact: Bool = false) {
        self.url = url
        self.isCompact = isCompact
        self.isExtraCompact = isExtraCompact
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: isExtraCompact ? 3 : (isCompact ? 6 : 12)) {
            if isLoading {
                // Loading state
                RoundedRectangle(cornerRadius: isExtraCompact ? 4 : (isCompact ? 6 : 8))
                    .fill(Color(NSColor.controlBackgroundColor))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        VStack(spacing: isExtraCompact ? 3 : (isCompact ? 6 : 12)) {
                            ProgressView()
                                .scaleEffect(isExtraCompact ? 0.5 : (isCompact ? 0.7 : 1.0))
                                .controlSize(isExtraCompact ? .mini : (isCompact ? .small : .regular))
                            Text("Loading preview...")
                                .font(isExtraCompact ? .caption2 : (isCompact ? .caption2 : .body))
                                .foregroundColor(.secondary)
                        }
                    )
            } else if let preview = previewData {
                // Preview content
                VStack(alignment: .leading, spacing: isExtraCompact ? 3 : (isCompact ? 6 : 12)) {
                    // Thumbnail
                    Group {
                        if let image = preview.image {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            AsyncImage(url: URL(string: preview.imageURL ?? "")) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: isExtraCompact ? 3 : (isCompact ? 4 : 8))
                                    .fill(Color(NSColor.controlBackgroundColor))
                                    .overlay(
                                        Image(systemName: "photo")
                                            .foregroundColor(.secondary)
                                            .font(isExtraCompact ? .caption2 : (isCompact ? .caption2 : .title2))
                                    )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: isExtraCompact ? 40 : (isCompact ? 60 : 180))
                    .clipShape(RoundedRectangle(cornerRadius: isExtraCompact ? 3 : (isCompact ? 4 : 8)))
                    
                    // Content
                    VStack(alignment: .leading, spacing: isExtraCompact ? 1 : (isCompact ? 2 : 8)) {
                        Text(preview.title ?? "Link")
                            .font(isExtraCompact ? .caption2 : (isCompact ? .caption : .headline))
                            .fontWeight(isExtraCompact ? .medium : (isCompact ? .medium : .semibold))
                            .lineLimit(isExtraCompact ? 1 : (isCompact ? 2 : 3))
                        
                        if let description = preview.description, !isExtraCompact {
                            Text(description)
                                .font(isCompact ? .caption2 : .body)
                                .foregroundColor(.secondary)
                                .lineLimit(isCompact ? 2 : 4)
                        }
                        
                        if isCompact || isExtraCompact {
                            Text(URL(string: url)?.host ?? url)
                                .font(isExtraCompact ? .caption2 : .caption2)
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
                VStack(alignment: .leading, spacing: isExtraCompact ? 2 : (isCompact ? 4 : 12)) {
                    HStack {
                        Image(systemName: "link")
                            .foregroundColor(.blue)
                            .font(isExtraCompact ? .caption2 : (isCompact ? .caption2 : .title2))
                        Text(isExtraCompact ? "Link" : (isCompact ? "Link" : "Link Preview"))
                            .font(isExtraCompact ? .caption2 : (isCompact ? .caption : .headline))
                            .fontWeight(isExtraCompact ? .medium : (isCompact ? .medium : .semibold))
                    }
                    
                    if !isCompact && !isExtraCompact {
                        Text("Unable to load preview for this URL")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(URL(string: url)?.host ?? url)
                        .font(isExtraCompact ? .caption2 : (isCompact ? .caption2 : .caption))
                        .foregroundColor(.secondary)
                        .lineLimit(isExtraCompact ? 1 : 2)
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

        let provider = LPMetadataProvider()
        Task {
            do {
                let metadata = try await provider.startFetchingMetadata(for: url)
                let imageProvider = metadata.imageProvider
                var displayImage: NSImage?

                if let imageProvider = imageProvider {
                    displayImage = try await withCheckedThrowingContinuation { continuation in
                        imageProvider.loadObject(ofClass: NSImage.self) { image, error in
                            if let error = error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(returning: image as? NSImage)
                            }
                        }
                    }
                }

                let data = LinkPreviewData(
                    title: metadata.title,
                    description: nil, // Description is not directly available in LPLinkMetadata
                    imageURL: nil, // We get the image directly, not the URL
                    siteName: metadata.url?.host,
                    url: metadata.originalURL?.absoluteString ?? self.url,
                    image: displayImage
                )

                await MainActor.run {
                    self.previewData = data
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}