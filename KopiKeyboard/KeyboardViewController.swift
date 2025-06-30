//
//  KeyboardViewController.swift
//  KopiKeyboard
//
//  Created by Wan Menzy on 25/06/2025.
//

import UIKit
import CoreData

// MARK: - ContentType for Keyboard Extension
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
}

class KeyboardViewController: UIInputViewController {
    
    // MARK: - Properties
    private var clipboardItems: [SimpleClipboardItem] = []
    
    // Check if keyboard has app group access
    private func hasAppGroupAccess() -> Bool {
        guard let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.menzy.kopi") else {
            return false
        }
        
        // Try to create a test file to verify write access
        let testFileURL = appGroupURL.appendingPathComponent("keyboard_test.txt")
        do {
            try "test".write(to: testFileURL, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: testFileURL)
            return true
        } catch {
            return false
        }
    }
    
    // Simple struct for keyboard extension
    struct SimpleClipboardItem {
        let id: String
        let content: String
        let contentType: String
        let createdAt: Date
        let sourceAppName: String?
        let sourceAppIcon: Data?
    }
    private var keyboardView: UIView!
    private var stackView: UIStackView!
    private var clipboardStackView: UIStackView!
    private var searchBar: UISearchBar!
    private var noItemsLabel: UILabel!
    private var errorLabel: UILabel!
    
    // Core Data - Use shared app group container
    private lazy var persistentContainer: NSPersistentContainer = {
        // Try to find the model in the main bundle first, then in the keyboard extension bundle
        guard let modelURL = Bundle.main.url(forResource: "kopi", withExtension: "momd") ??
                             Bundle(for: KeyboardViewController.self).url(forResource: "kopi", withExtension: "momd") else {
            print("❌ [Keyboard] Could not find Core Data model file")
            // Create a fallback container
            return NSPersistentContainer(name: "kopi")
        }
        
        guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
            print("❌ [Keyboard] Could not load Core Data model")
            return NSPersistentContainer(name: "kopi")
        }
        
        let container = NSPersistentContainer(name: "kopi", managedObjectModel: model)
        
        // Configure store URL to use app group
        if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.menzy.kopi") {
            let storeURL = appGroupURL.appendingPathComponent("kopi.sqlite")
            print("✅ [Keyboard] Using store URL: \(storeURL)")
            
            let description = NSPersistentStoreDescription(url: storeURL)
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            
            container.persistentStoreDescriptions = [description]
        } else {
            print("❌ [Keyboard] Could not access app group container")
        }
        
        container.loadPersistentStores { _, error in
            if let error = error {
                print("❌ [Keyboard] Core Data error: \(error)")
            } else {
                print("✅ [Keyboard] Core Data loaded successfully")
            }
        }
        
        return container
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupKeyboardUI()
        
        // Check permissions first
        checkPermissionsAndLoadData()
        
        // Listen for data changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dataDidChange),
            name: .NSPersistentStoreRemoteChange,
            object: nil
        )
    }
    
    private func checkPermissionsAndLoadData() {
        // Check if we have full access (built-in property)
        guard hasFullAccess else {
            showError("Please enable 'Allow Full Access' for Kopi Keyboard in Settings > General > Keyboard > Keyboards")
            return
        }
        
        // Check if we can access the app group
        guard hasAppGroupAccess() else {
            showError("Cannot access shared app data. Please check app group permissions.")
            return
        }
        
        guard let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.menzy.kopi") else {
            showError("Cannot access shared app data.")
            return
        }
        
        print("✅ [Keyboard] App group URL: \(appGroupURL)")
        loadClipboardItems()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkPermissionsAndLoadData()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - UI Setup
    
    private func setupKeyboardUI() {
        // Main container
        keyboardView = UIView()
        keyboardView.backgroundColor = UIColor.systemBackground
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardView)
        
        // Create main stack view
        stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        keyboardView.addSubview(stackView)
        
        // Header with search and next keyboard button
        let headerView = createHeaderView()
        stackView.addArrangedSubview(headerView)
        
        // Clipboard items container
        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        clipboardStackView = UIStackView()
        clipboardStackView.axis = .horizontal
        clipboardStackView.spacing = 12
        clipboardStackView.alignment = .top
        clipboardStackView.translatesAutoresizingMaskIntoConstraints = false
        
        scrollView.addSubview(clipboardStackView)
        stackView.addArrangedSubview(scrollView)
        
        // Setup constraints for scroll view and clipboard stack
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 160),
            
            clipboardStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 12),
            clipboardStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -12),
            clipboardStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            clipboardStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            clipboardStackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
        
        // No items label
        noItemsLabel = UILabel()
        noItemsLabel.text = "No clipboard items found\nMake sure Kopi has access to your data"
        noItemsLabel.textAlignment = .center
        noItemsLabel.numberOfLines = 0
        noItemsLabel.textColor = .secondaryLabel
        noItemsLabel.font = UIFont.systemFont(ofSize: 14)
        noItemsLabel.isHidden = true
        stackView.addArrangedSubview(noItemsLabel)
        
        // Error label
        errorLabel = UILabel()
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.textColor = .systemRed
        errorLabel.font = UIFont.systemFont(ofSize: 12)
        errorLabel.isHidden = true
        stackView.addArrangedSubview(errorLabel)
        
        // Constraints
        NSLayoutConstraint.activate([
            keyboardView.topAnchor.constraint(equalTo: view.topAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            keyboardView.heightAnchor.constraint(equalToConstant: 280),
            
            stackView.topAnchor.constraint(equalTo: keyboardView.topAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: keyboardView.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: keyboardView.trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: keyboardView.bottomAnchor, constant: -8),
            
            clipboardStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            clipboardStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            clipboardStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            clipboardStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            clipboardStackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }
    
    private func createHeaderView() -> UIView {
        let headerView = UIView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Search bar
        searchBar = UISearchBar()
        searchBar.placeholder = "Search clipboard..."
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        
        // Next keyboard button
        let nextKeyboardButton = UIButton(type: .system)
        nextKeyboardButton.setTitle("🌐", for: .normal)
        nextKeyboardButton.titleLabel?.font = UIFont.systemFont(ofSize: 20)
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false
        
        headerView.addSubview(searchBar)
        headerView.addSubview(nextKeyboardButton)
        
        NSLayoutConstraint.activate([
            headerView.heightAnchor.constraint(equalToConstant: 44),
            
            searchBar.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            searchBar.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            searchBar.trailingAnchor.constraint(equalTo: nextKeyboardButton.leadingAnchor, constant: -8),
            
            nextKeyboardButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            nextKeyboardButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            nextKeyboardButton.widthAnchor.constraint(equalToConstant: 44),
            nextKeyboardButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        return headerView
    }
    
    // MARK: - Data Loading
    
    private func loadClipboardItems() {
        print("🔍 [Keyboard] Starting to load clipboard items...")
        
        // Check if app group container exists
        if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.menzy.kopi") {
            print("✅ [Keyboard] App group container found at: \(appGroupURL)")
            let storeURL = appGroupURL.appendingPathComponent("kopi.sqlite")
            print("🔍 [Keyboard] Looking for Core Data store at: \(storeURL)")
            print("🔍 [Keyboard] Store exists: \(FileManager.default.fileExists(atPath: storeURL.path))")
            
            // List all files in app group container
            do {
                let files = try FileManager.default.contentsOfDirectory(at: appGroupURL, includingPropertiesForKeys: nil)
                print("🔍 [Keyboard] Files in app group container:")
                for file in files {
                    print("  - \(file.lastPathComponent)")
                }
            } catch {
                print("❌ [Keyboard] Could not list app group container contents: \(error)")
            }
        } else {
            print("❌ [Keyboard] App group container not accessible")
        }
        
        let context = persistentContainer.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "ClipboardItem")
        request.predicate = NSPredicate(format: "markedAsDeleted == NO")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = 20 // Limit for keyboard performance
        
        do {
            let managedObjects = try context.fetch(request)
            print("🔍 [Keyboard] Fetched \(managedObjects.count) raw objects from Core Data")
            
            if managedObjects.isEmpty {
                print("⚠️ [Keyboard] No objects found in Core Data. This could mean:")
                print("  1. No clipboard items have been created in the main app")
                print("  2. The Core Data store is not shared properly")
                print("  3. The keyboard is accessing a different store")
            }
            
            clipboardItems = managedObjects.compactMap { managedObject in
                guard let id = managedObject.value(forKey: "id") as? UUID,
                      let content = managedObject.value(forKey: "content") as? String,
                      let contentType = managedObject.value(forKey: "contentType") as? String,
                      let createdAt = managedObject.value(forKey: "createdAt") as? Date else {
                    print("⚠️ [Keyboard] Skipping object with missing required fields")
                    print("  - id: \(managedObject.value(forKey: "id") ?? "nil")")
                    print("  - content: \(managedObject.value(forKey: "content") ?? "nil")")
                    print("  - contentType: \(managedObject.value(forKey: "contentType") ?? "nil")")
                    print("  - createdAt: \(managedObject.value(forKey: "createdAt") ?? "nil")")
                    return nil
                }
                
                let sourceAppName = managedObject.value(forKey: "sourceAppName") as? String
                let sourceAppIcon = managedObject.value(forKey: "sourceAppIcon") as? Data
                
                print("✅ [Keyboard] Found clipboard item: \(String(content.prefix(50)))")
                
                return SimpleClipboardItem(
                    id: id.uuidString,
                    content: content,
                    contentType: contentType,
                    createdAt: createdAt,
                    sourceAppName: sourceAppName,
                    sourceAppIcon: sourceAppIcon
                )
            }
            print("✅ [Keyboard] Successfully loaded \(clipboardItems.count) clipboard items")
            updateUI()
        } catch {
            print("❌ [Keyboard] Failed to load clipboard items: \(error)")
            print("❌ [Keyboard] Error details: \(error.localizedDescription)")
            showError("Failed to load clipboard items: \(error.localizedDescription)")
        }
    }
    
    private func searchClipboardItems(_ searchText: String) {
        let context = persistentContainer.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "ClipboardItem")
        
        var predicates: [NSPredicate] = [NSPredicate(format: "markedAsDeleted == NO")]
        
        if !searchText.isEmpty {
            predicates.append(NSPredicate(format: "content CONTAINS[cd] %@", searchText))
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = 20
        
        do {
            let managedObjects = try context.fetch(request)
            clipboardItems = managedObjects.compactMap { managedObject in
                guard let id = managedObject.value(forKey: "id") as? UUID,
                      let content = managedObject.value(forKey: "content") as? String,
                      let contentType = managedObject.value(forKey: "contentType") as? String,
                      let createdAt = managedObject.value(forKey: "createdAt") as? Date else {
                    return nil
                }
                
                let sourceAppName = managedObject.value(forKey: "sourceAppName") as? String
                let sourceAppIcon = managedObject.value(forKey: "sourceAppIcon") as? Data
                
                return SimpleClipboardItem(
                    id: id.uuidString,
                    content: content,
                    contentType: contentType,
                    createdAt: createdAt,
                    sourceAppName: sourceAppName,
                    sourceAppIcon: sourceAppIcon
                )
            }
            updateUI()
        } catch {
            print("❌ [Keyboard] Search failed: \(error)")
            showError("Search failed")
        }
    }
    
    // MARK: - UI Updates
    
    private func updateUI() {
        DispatchQueue.main.async {
            // Clear existing views
            self.clipboardStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            
            if self.clipboardItems.isEmpty {
                self.noItemsLabel.isHidden = false
                self.errorLabel.isHidden = true
            } else {
                self.noItemsLabel.isHidden = true
                self.errorLabel.isHidden = true
                
                // Add clipboard item views
                for item in self.clipboardItems {
                    let itemView = self.createItemView(for: item)
                    self.clipboardStackView.addArrangedSubview(itemView)
                }
            }
        }
    }
    
    private func createItemView(for item: SimpleClipboardItem) -> UIView {
        let cardView = UIView()
        cardView.backgroundColor = UIColor.secondarySystemBackground
        cardView.layer.cornerRadius = 16
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOffset = CGSize(width: 0, height: 2)
        cardView.layer.shadowOpacity = 0.05
        cardView.layer.shadowRadius = 8
        cardView.translatesAutoresizingMaskIntoConstraints = false
        
        // Header with content type, timestamp, and app icon
        let headerView = UIView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Content type and timestamp
        let contentType = ContentType(rawValue: item.contentType) ?? .text
        let timeAgo = formatTimeAgo(item.createdAt)
        
        let typeLabel = UILabel()
        typeLabel.text = contentType.displayName
        typeLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        typeLabel.textColor = .label
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let timeLabel = UILabel()
        timeLabel.text = timeAgo
        timeLabel.font = UIFont.systemFont(ofSize: 14)
        timeLabel.textColor = .secondaryLabel
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // App icon
        var appIconView: UIImageView?
        if let iconData = item.sourceAppIcon, let image = UIImage(data: iconData) {
            let iconView = UIImageView(image: image)
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.contentMode = .scaleAspectFit
            iconView.layer.cornerRadius = 4
            iconView.clipsToBounds = true
            appIconView = iconView
        }
        
        // Content preview based on type
        let contentView: UIView
        switch contentType {
        case .text:
            let label = UILabel()
            label.text = String(item.content.prefix(120))
            label.font = UIFont.systemFont(ofSize: 16)
            label.textColor = .label
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView = label
            
        case .image:
            if let imageData = Data(base64Encoded: item.content), let image = UIImage(data: imageData) {
                let imageView = UIImageView(image: image)
                imageView.contentMode = .scaleAspectFill
                imageView.clipsToBounds = true
                imageView.translatesAutoresizingMaskIntoConstraints = false
                contentView = imageView
            } else {
                let label = UILabel()
                label.text = "Image"
                label.font = UIFont.systemFont(ofSize: 16)
                label.textColor = .secondaryLabel
                label.translatesAutoresizingMaskIntoConstraints = false
                contentView = label
            }
            
        case .url:
            let linkPreview = LinkPreviewCard(url: item.content)
            linkPreview.translatesAutoresizingMaskIntoConstraints = false
            contentView = linkPreview
            
        case .file:
            let label = UILabel()
            label.text = String(item.content.prefix(120))
            label.font = UIFont.systemFont(ofSize: 16)
            label.textColor = .systemBlue
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView = label
        }
        
        // Layout header
        headerView.addSubview(typeLabel)
        headerView.addSubview(timeLabel)
        if let iconView = appIconView {
            headerView.addSubview(iconView)
        }
        
        // Layout card
        cardView.addSubview(headerView)
        cardView.addSubview(contentView)
        
        // Card constraints
        let cardWidth: CGFloat = 200
        let cardHeight: CGFloat = 180
        
        NSLayoutConstraint.activate([
            cardView.widthAnchor.constraint(equalToConstant: cardWidth),
            cardView.heightAnchor.constraint(equalToConstant: cardHeight),
            
            headerView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            headerView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            headerView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            headerView.heightAnchor.constraint(equalToConstant: 24),
            
            typeLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            typeLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            timeLabel.leadingAnchor.constraint(equalTo: typeLabel.trailingAnchor, constant: 8),
            timeLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            contentView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 12),
            contentView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            contentView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            contentView.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -16)
        ])
        
        // App icon constraints
        if let iconView = appIconView {
            NSLayoutConstraint.activate([
                iconView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
                iconView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 20),
                iconView.heightAnchor.constraint(equalToConstant: 20)
            ])
        }
        
        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(itemTapped(_:)))
        cardView.addGestureRecognizer(tapGesture)
        cardView.isUserInteractionEnabled = true
        cardView.tag = item.id.hashValue
        
        return cardView
    }
    
    private func showError(_ message: String) {
        DispatchQueue.main.async {
            self.errorLabel.text = message
            self.errorLabel.isHidden = false
            self.noItemsLabel.isHidden = true
        }
    }
    
    // MARK: - Actions
    
    @objc private func itemTapped(_ sender: UITapGestureRecognizer) {
        guard let tappedView = sender.view else { return }
        let itemId = tappedView.tag
        
        if let item = clipboardItems.first(where: { $0.id.hashValue == itemId }) {
            pasteClipboardItem(item)
        }
    }
    
    private func pasteClipboardItem(_ item: SimpleClipboardItem) {
        let content = item.content
        
        // Insert the text into the current text input
        textDocumentProxy.insertText(content)
        
        // Provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        print("📋 [Keyboard] Pasted content: \(content.prefix(50))...")
    }
    
    @objc private func dataDidChange() {
        print("📡 [Keyboard] Data changed, reloading...")
        loadClipboardItems()
    }
    
    // MARK: - Helper Methods
    
    private func formatTimeAgo(_ date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 {
            return "now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours)h"
        } else {
            let days = Int(timeInterval / 86400)
            return "\(days)d"
        }
    }
    
    // MARK: - Required Overrides
    
    override func updateViewConstraints() {
        super.updateViewConstraints()
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
    }
    
    override func textWillChange(_ textInput: UITextInput?) {
        // The app is about to change the document's contents
    }
    
    override func textDidChange(_ textInput: UITextInput?) {
        // The app has just changed the document's contents
        updateAppearanceForCurrentMode()
    }
    
    private func updateAppearanceForCurrentMode() {
        let isDark = textDocumentProxy.keyboardAppearance == .dark
        keyboardView.backgroundColor = isDark ? UIColor.black : UIColor.systemBackground
    }
}



// MARK: - UISearchBarDelegate

extension KeyboardViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        // Debounce search to improve performance
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(performSearch), object: nil)
        perform(#selector(performSearch), with: nil, afterDelay: 0.3)
    }
    
    @objc private func performSearch() {
        let searchText = searchBar.text ?? ""
        searchClipboardItems(searchText)
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}
