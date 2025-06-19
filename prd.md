
Product Name: Kopi

Overview

Kopi is a clipboard history application that allows users to seamlessly copy and access clipboard data across their MacBook and iPhone. It will feature automatic clipboard monitoring on macOS and an iOS app—optionally with a custom keyboard extension—for accessing, pasting, and managing previously copied items. The clipboard data is synced securely in real time via iCloud.

Goals
	•	Maintain a persistent clipboard history across MacBook and iPhone
	•	Enable users to access and reuse clipboard items efficiently
	•	Ensure data privacy and synchronization reliability
	•	Provide a smooth user experience through native macOS and iOS interfaces
	•	Respect user privacy by avoiding sensitive data capture
	•	Provide reliable offline functionality with seamless sync when online

Key Features

macOS App
	•	Clipboard monitoring using NSPasteboard with privacy-aware detection
	•	Storing history of copied texts, links, and images (excludes videos)
	•	iCloud syncing of clipboard history
	•	Quick access menu from menu bar for clipboard history
	•	App-based segmentation with source app logos and names
	•	Option to pin or favorite specific clipboard items
	•	Keyboard shortcuts for quick access (configurable)
	•	Search functionality across clipboard history
	•	Filter and group by source application
	•	User-configurable data retention settings (indefinite by default)
	•	Automatic sensitive data detection and exclusion
	•	Visual sync indicators and manual refresh option

iOS App
	•	SwiftUI-based app UI
	•	View synced clipboard history with search
	•	Copy to clipboard with one tap
	•	Manual item deletion and organization
	•	Custom keyboard extension (optional):
		◦	Displays recent clipboard items for quick paste
		◦	Keyboard works within most iOS apps (excluding secure fields)
		◦	Requires "Allow Full Access" permission for network sync
		◦	Includes globe key for keyboard switching

Syncing
	•	Use iCloud with CloudKit for private, seamless syncing between devices
	•	Maintain data consistency with UUIDs and timestamps
	•	Conflict resolution rules: most recent update wins
	•	Offline behavior: local storage with sync queue for when connectivity returns
	•	Incremental sync for large datasets with pagination
	•	Retry mechanisms for failed syncs with exponential backoff
	•	Sync reliability target: >95% success rate

Non-Goals
	•	Sharing clipboard with third-party users
	•	Supporting platforms outside Apple ecosystem (e.g., Android, Windows)

Architecture Overview
	•	macOS Component: Background agent monitors clipboard, stores data locally, and syncs to iCloud
	•	iOS Component: Fetches from iCloud database and presents UI for interaction (app + optional keyboard extension)
	•	Data Model: ClipboardItem {
		◦	id: UUID
		◦	type: String (text, url, image)
		◦	content: Data
		◦	contentPreview: String (truncated for display)
		◦	timestamp: Date
		◦	isPinned: Bool
		◦	deviceOrigin: String
		◦	sourceApp: String (bundle identifier)
		◦	sourceAppName: String (display name)
		◦	sourceAppIcon: Data (app icon for UI display)
		◦	fileSize: Int64
		◦	isTransient: Bool (for temporary items)
		◦	isSensitive: Bool (for detected sensitive content)
	}

Technical Requirements
	•	Languages: Swift (macOS + iOS)
	•	Frameworks: CloudKit, SwiftUI, AppKit, UIKit, Keyboard Extension API
	•	iCloud Container: Configured for app group sharing between iOS app and extension
	•	Security: 
		◦	iCloud Private Database with end-to-end encryption
		◦	AES-256 encryption for local storage
		◦	Keychain storage for sensitive configuration
		◦	Respect NSPasteboard privacy markers (org.nspasteboard.ConcealedType, etc.)
	•	Permissions:
		◦	macOS: NSPasteboard access (will trigger privacy alerts in macOS 16+), Accessibility permissions for source app detection, System Events access for app information and icons
		◦	iOS: Keyboard extension with RequestsOpenAccess=true for network sync
	•	Content Limits:
		◦	Supported: Text, URLs, Images (PNG, JPEG, GIF)
		◦	Excluded: Videos, executables, files >10MB
		◦	Automatic sensitive data detection and exclusion

Success Metrics
	•	Latency of sync between devices < 3s (ideal)
	•	< 5% crash rate across all sessions
	•	Users can find and paste clipboard content in ≤ 2 taps or clicks
	•	Sync reliability >95% success rate
	•	Daily active usage: >70% of users access clipboard history daily
	•	User satisfaction score >4.5/5.0
	•	Average items accessed per session >3

User Onboarding & Setup
	macOS Setup:
		◦	Guide users through granting NSPasteboard access
		◦	Guide user to System Settings > Privacy & Security > Accessibility for source app detection
		◦	Optional: Enable System Events access for app icon retrieval
		◦	Explain privacy alerts and direct to System Settings for "always allow"
		◦	Provide clear explanation of why permissions are needed for source app detection
		◦	Graceful degradation when accessibility access is unavailable
		◦	Test onboarding flow with macOS 16+ privacy changes
	iOS Setup:
		◦	Guide users to Settings > General > Keyboard > Keyboards > Add New Keyboard
		◦	Explain "Allow Full Access" requirement for sync functionality
		◦	Provide visual step-by-step setup instructions
		◦	Clear explanation of keyboard extension limitations

Privacy & Sensitive Data Handling
	•	Rules-Based Privacy System (macOS):
		◦	Configurable rules interface similar to firewall or privacy settings
		◦	Default exclusions for sensitive sources:
			▪	Screenshot utilities (built-in and third-party)
			▪	Password managers (1Password, Bitwarden, Keychain Access, etc.)
			▪	Banking and financial applications
			▪	System utilities and secure input fields
		◦	User-configurable allow/block lists:
			▪	Add specific applications to exclusion list
			▪	Create exceptions for trusted applications
			▪	Temporary rules (e.g., "Allow for next 10 minutes")
			▪	Rule priorities and inheritance
	•	Automatic Detection:
		◦	Password patterns (consecutive special characters, common password formats)
		◦	Credit card numbers (Luhn algorithm validation)
		◦	SSN and other ID number patterns
		◦	API keys and tokens (common prefixes and formats)
	•	Respect Privacy Markers:
		◦	org.nspasteboard.ConcealedType (sensitive content)
		◦	org.nspasteboard.TransientType (temporary content)
		◦	org.nspasteboard.AutoGeneratedType (app-generated content)
	•	User Controls:
		◦	Global toggle for clipboard monitoring
		◦	Rules management interface with visual indicators
		◦	Manual marking of items as sensitive
		◦	Automatic exclusion of secure text fields
		◦	Export/import of privacy settings and rules
		◦	Quick access to temporarily disable monitoring

Error Handling & Reliability
	•	Sync Failures:
		◦	Exponential backoff retry (1s, 2s, 4s, 8s, max 60s)
		◦	Queue failed operations for retry when connectivity returns
		◦	User notification for persistent sync issues
	•	Data Corruption:
		◦	Checksum validation for clipboard items
		◦	Automatic recovery from local backup
		◦	Conflict resolution with user choice for important items
	•	Performance:
		◦	Lazy loading for large clipboard histories
		◦	Image compression for sync optimization
		◦	Background processing for non-critical operations

Future Considerations
	•	Tags or folders for organizing clipboard entries
	•	Analytics dashboard to show copy/paste trends
	•	Universal search across clipboard history
	•	Cross-device clipboard editing
	•	Smart suggestions based on context
	•	Integration with Shortcuts app
	•	Team/shared clipboard functionality

Risks and Mitigations
	•	Clipboard security concerns: 
		◦	Only sync when user has granted explicit permission
		◦	No background reads on iOS
		◦	Automatic detection and exclusion of sensitive content
		◦	Respect app-level clipboard restrictions
		◦	Clear onboarding about privacy practices
	•	iCloud sync delays: 
		◦	Allow manual refresh as fallback
		◦	Optimize CloudKit usage with batching and compression
		◦	Implement retry logic with exponential backoff
	•	macOS 16+ Privacy Changes:
		◦	Adapt to new NSPasteboard privacy alerts
		◦	Provide clear user guidance for granting "always allow" permission
		◦	Implement proper onboarding flow directing users to System Settings
	•	iOS Keyboard Extension Limitations:
		◦	Cannot access secure text fields (passwords)
		◦	Requires "Allow Full Access" for network functionality
		◦	May be disabled by banking/HIPAA apps

⸻

End of Document