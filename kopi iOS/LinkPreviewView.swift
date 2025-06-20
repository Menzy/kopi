//
//  LinkPreviewView.swift
//  kopi ios
//
//  Created by AI Assistant on 20/06/2025.
//

import SwiftUI
import WebKit

// Link Preview Data Model
struct LinkPreviewData {
    let title: String?
    let description: String?
    let imageURL: String?
    let siteName: String?
    let url: String
}

// Link Preview Card Component
struct LinkPreviewCard: View {
    let url: String
    @State private var previewData: LinkPreviewData?
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                // Loading state
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        VStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading preview...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    )
            } else if let preview = previewData {
                // Preview content
                VStack(alignment: .leading, spacing: 8) {
                    // Thumbnail
                    AsyncImage(url: URL(string: preview.imageURL ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.systemGray5))
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    // Content
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preview.title ?? "Link")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                        
                        if let description = preview.description {
                            Text(description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        
                        Text(URL(string: url)?.host ?? url)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                // Error state - fallback to simple URL display
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "link")
                            .foregroundColor(.blue)
                        Text("Link")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    
                    Text(URL(string: url)?.host ?? url)
                        .font(.caption)
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

// WebView component for iOS
struct WebView: UIViewRepresentable {
    let url: URL?
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.isUserInteractionEnabled = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if let url = url {
            let request = URLRequest(url: url)
            uiView.load(request)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // Handle loading errors gracefully
            let errorHTML = """
            <html>
            <head>
                <style>
                    body {
                        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                        height: 100vh;
                        margin: 0;
                        background-color: #f5f5f5;
                        color: #666;
                        font-size: 14px;
                    }
                    .error-container {
                        text-align: center;
                        padding: 20px;
                    }
                    .error-icon {
                        font-size: 24px;
                        margin-bottom: 8px;
                    }
                </style>
            </head>
            <body>
                <div class="error-container">
                    <div class="error-icon">🌐</div>
                    <div>Unable to load webpage</div>
                </div>
            </body>
            </html>
            """
            webView.loadHTMLString(errorHTML, baseURL: nil)
        }
    }
} 