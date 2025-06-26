# Kopi Keyboard Extension

This is the iOS keyboard extension for Kopi that allows users to access their clipboard history directly from any app's keyboard.

## Features

- ✅ Access clipboard history from any app
- ✅ Search through clipboard items
- ✅ Tap to paste clipboard content
- ✅ Real-time sync with main Kopi app
- ✅ App group data sharing
- ✅ Support for text, URLs, and other content types

## Setup Instructions

### 1. Build and Install
1. Build the project in Xcode
2. Install the app on your iOS device
3. The keyboard extension will be included automatically

### 2. Enable the Keyboard
1. Go to **Settings** > **General** > **Keyboard** > **Keyboards**
2. Tap **Add New Keyboard...**
3. Find and select **Kopi Keyboard**
4. **IMPORTANT**: Tap on **Kopi Keyboard** in the list and enable **Allow Full Access**
   - This is required for the keyboard to access your clipboard data
   - Without this, the keyboard cannot read from the shared app group

### 3. Using the Keyboard
1. Open any app with a text field (Messages, Notes, etc.)
2. Tap the text field to bring up the keyboard
3. Tap the globe icon (🌐) to switch between keyboards until you see Kopi
4. Your recent clipboard items will appear
5. Tap any item to paste it into the text field
6. Use the search bar to find specific clipboard content

## Technical Details

### App Group Integration
- Uses `group.com.menzy.kopi` for data sharing
- Accesses the same Core Data store as the main app
- Real-time sync when data changes

### Permissions Required
- **Allow Full Access**: Required to access shared app group data
- This permission is necessary for the keyboard to function properly

### Performance Optimizations
- Limits to 20 most recent items for keyboard performance
- Debounced search to prevent excessive queries
- Efficient Core Data queries with proper indexing

## Troubleshooting

### No Clipboard Items Showing
1. Ensure "Allow Full Access" is enabled for Kopi Keyboard
2. Check that the main Kopi app has clipboard items
3. Try switching away from the keyboard and back
4. Restart the app if needed

### Keyboard Not Appearing
1. Make sure Kopi Keyboard is added in Settings > Keyboards
2. Tap the globe icon multiple times to cycle through keyboards
3. Check that the keyboard extension is properly installed

### Search Not Working
1. Ensure there are clipboard items to search through
2. Try different search terms
3. Check that "Allow Full Access" is enabled

## Development Notes

### Phase 5 Implementation Status
- ✅ Keyboard extension target created
- ✅ App group configuration
- ✅ Core Data integration
- ✅ Custom keyboard UI
- ✅ Search functionality
- ✅ Tap-to-paste functionality
- ✅ Real-time data sync

### Next Steps for Production
- [ ] Add more content type support (images, files)
- [ ] Implement keyboard shortcuts
- [ ] Add haptic feedback improvements
- [ ] Optimize for different device sizes
- [ ] Add accessibility support
- [ ] Performance testing with large datasets

## Security & Privacy

- The keyboard extension only accesses data from your own Kopi app
- No data is sent to external servers
- All data remains on your device and iCloud (if enabled)
- "Allow Full Access" is only used for app group data sharing 