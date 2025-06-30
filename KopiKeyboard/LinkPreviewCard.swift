//
//  LinkPreviewCard.swift
//  KopiKeyboard
//
//  Created by AI Assistant on 20/06/2025.
//

import UIKit
import LinkPresentation

class LinkPreviewCard: UIView {
    private let url: String
    private var imageView: UIImageView!
    private var titleLabel: UILabel!
    private var urlLabel: UILabel!
    private var loadingIndicator: UIActivityIndicatorView!
    
    init(url: String) {
        self.url = url
        super.init(frame: .zero)
        setupUI()
        fetchLinkPreview()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 8
        clipsToBounds = true
        
        // Image view
        imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .systemGray6
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        
        // Title label
        titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        // URL label
        urlLabel = UILabel()
        urlLabel.font = .systemFont(ofSize: 12)
        urlLabel.textColor = .secondaryLabel
        urlLabel.numberOfLines = 1
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(urlLabel)
        
        // Loading indicator
        loadingIndicator = UIActivityIndicatorView(style: .medium)
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(loadingIndicator)
        
        NSLayoutConstraint.activate([
            // Image view constraints
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 80),
            
            // Title label constraints
            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            
            // URL label constraints
            urlLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            urlLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            urlLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            urlLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
            
            // Loading indicator constraints
            loadingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        loadingIndicator.startAnimating()
    }
    
    private func fetchLinkPreview() {
        guard let url = URL(string: url) else {
            showError()
            return
        }
        
        let provider = LPMetadataProvider()
        Task {
            do {
                let metadata = try await provider.startFetchingMetadata(for: url)
                let imageProvider = metadata.imageProvider
                
                if let imageProvider = imageProvider {
                    let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage?, Error>) in
                        imageProvider.loadObject(ofClass: UIImage.self) { image, error in
                            if let error = error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(returning: image as? UIImage)
                            }
                        }
                    }
                    
                    await MainActor.run {
                        self.imageView.image = image
                    }
                }
                
                await MainActor.run {
                    self.titleLabel.text = metadata.title
                    self.urlLabel.text = url.host
                    self.loadingIndicator.stopAnimating()
                }
            } catch {
                await MainActor.run {
                    self.showError()
                }
            }
        }
    }
    
    private func showError() {
        loadingIndicator.stopAnimating()
        imageView.image = UIImage(systemName: "link")
        imageView.contentMode = .center
        imageView.tintColor = .systemBlue
        titleLabel.text = "Link"
        urlLabel.text = URL(string: url)?.host ?? url
    }
}