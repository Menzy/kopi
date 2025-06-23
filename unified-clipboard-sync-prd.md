# Unified Clipboard ID Sync PRD
*Cross-Device Clipboard Management with Synchronized IDs*

## Overview

Enhance the Kopi app to ensure that clipboard items copied on one device maintain the same UUID across all devices (macOS, iOS, and iCloud). This enables unified control where deleting, editing, or managing a clipboard item on any device propagates the changes to all other devices automatically.

## Current State

- **macOS**: `ClipboardMonitor` detects changes every 0.05s, creates items with unique UUIDs
- **iOS**: `ClipboardService` detects changes every 0.5s, creates items with unique UUIDs  
- **Universal Clipboard**: Works natively, but each device creates separate records
- **CloudKit Sync**: Syncs separate records with different IDs
- **Problem**: Same content exists with different IDs, no unified control

## Desired End State

When user copies "Happy Friday" on Macbook:
1. **Macbook** creates ClipboardItem with UUID `abc-123`
2. **Universal Clipboard** transfers to iPhone
3. **iPhone** detects the paste, recognizes it's from Macbook, uses same UUID `abc-123`
4. **iCloud** syncs the single record with UUID `abc-123`
5. **Delete from iPhone** → removes from iPhone + iCloud + Macbook
6. **Edit on Macbook** → updates on iPhone + iCloud

## Technical Requirements

### Core Data Model Changes
- [ ] Add `initiatingDevice: String` field to track which device created the item
- [ ] Add `syncSource: String` field to track how item was received (`local_copy`, `universal_clipboard`, `cloudkit_sync`)
- [ ] Add `canonicalID: UUID` field as the master identifier across devices
- [ ] Add `isTemporary: Bool` field for items awaiting ID resolution

### Device Identification System
- [ ] Create unique device identifiers for each installation
- [ ] Store device ID in UserDefaults/local storage
- [ ] Include device metadata (name, type, iOS/macOS version)

### Enhanced Detection Logic
- [ ] **Initiation Detection**: Distinguish between user-initiated copy vs received paste
- [ ] **Timing Windows**: Use precise timestamps to correlate Universal Clipboard transfers
- [ ] **Content Matching**: Advanced algorithm to match identical content across devices
- [ ] **Duplicate Prevention**: Avoid creating multiple records for the same logical clipboard action

## Implementation Phases

### Phase 1: Data Model & Device Identity (Week 1) ✅ **COMPLETED**
**Goal**: Establish foundation for cross-device identification

#### Tasks:
1. **Update Core Data Model** ✅
   - ✅ Add new fields to ClipboardItem entity (`canonicalID`, `initiatingDevice`, `syncSource`, `isTemporary`)
   - ✅ Create and test Core Data migration
   - ✅ Update iOS and macOS Persistence.swift files

2. **Device Identity System** ✅
   - ✅ Create `DeviceManager` class for unique device identification
   - ✅ Implement device registration and metadata collection (`mac-timestamp-random` / `ios-timestamp-random`)
   - ✅ Add device info to all clipboard item creation

3. **Testing** ✅
   - ✅ Verify migrations work on both platforms
   - ✅ Test device ID generation and persistence
   - ✅ Validate CloudKit schema updates

**Deliverables**: ✅ Updated data model, device identification system
**Status**: Both macOS and iOS builds passing, foundation ready for sync logic

### Phase 2: Enhanced Detection Engine (Week 2) ✅ **COMPLETED**
**Goal**: Implement smart detection of clipboard events and their sources

#### Tasks:
1. **Clipboard Event Classification** ✅
   - ✅ Update `ClipboardMonitor` (macOS) to detect initiation vs reception
   - ✅ Update `ClipboardService` (iOS) to classify clipboard events  
   - ✅ Implement timing-based correlation system

2. **Content Matching Algorithm** ✅
   - ✅ Create `ClipboardCorrelator` class with string similarity detection
   - ✅ Implement content hashing and similarity detection (Levenshtein distance)
   - ✅ Add temporal correlation (15-second window matching)

3. **Temporary Item Management** ✅
   - ✅ Create staging area for unresolved clipboard items (`isTemporary` flag)
   - ✅ Implement cleanup for abandoned temporary items
   - ✅ Add background resolution process via correlation

**Deliverables**: ✅ Smart clipboard event detection, content correlation system
**Status**: Both platforms integrated with ClipboardCorrelator, builds passing

### Phase 3: ID Synchronization Logic (Week 3) ✅ **COMPLETED**
**Goal**: Implement the core ID unification and sync logic

#### Tasks:
1. **ID Resolution System** ✅
   - ✅ Create `IDResolver` class to manage canonical ID assignment
   - ✅ Implement "master device" determination logic (timestamp priority)
   - ✅ Add ID update propagation mechanism with async batching

2. **CloudKit Integration** ✅
   - ✅ Create `CloudKitSyncManager` for enhanced sync operations
   - ✅ Implement conflict resolution for competing IDs (4 strategies)
   - ✅ Add retry mechanism and error handling for failed operations

3. **Cross-Device Communication** ✅
   - ✅ Leverage CloudKit remote change notifications
   - ✅ Implement immediate sync when ID resolution occurs
   - ✅ Add unified cross-device delete operations

**Deliverables**: ✅ Working ID synchronization across all three stores
**Status**: Both platforms integrated with IDResolver and CloudKitSyncManager, builds passing

### Phase 4: Unified Operations (Week 4) ✅ **COMPLETED**
**Goal**: Enable delete/edit operations to work across all devices  

#### Tasks:
1. **Cascading Delete System** ✅
   - ✅ Update delete operations to use canonical IDs
   - ✅ Implement CloudKit-based delete propagation 
   - ✅ Add local cleanup when remote deletes arrive

2. **Unified Edit Operations** ✅
   - ✅ Update edit operations to propagate changes
   - ✅ Implement conflict resolution for simultaneous edits (4 strategies)
   - ✅ Add change tracking and history with EditVersion system

3. **Organization Features** ✅
   - ✅ Implement unified favorites/pinning system
   - ✅ Add cross-device collections/folders
   - ✅ Create synchronized item ordering with batch operations

**Deliverables**: ✅ UnifiedOperationsManager with EditClipboardItemView, both platforms building
**Status**: Edit, delete, organize operations working across macOS/iOS/CloudKit

### Phase 5: Testing & Polish (Week 5)
**Goal**: Comprehensive testing and performance optimization

#### Tasks:
1. **Integration Testing**
   - Test all copy/paste scenarios across device combinations
   - Verify delete/edit propagation in various network conditions
   - Test offline-to-online sync scenarios

2. **Performance Optimization**
   - Optimize clipboard monitoring frequency
   - Reduce CloudKit API calls
   - Improve battery usage on iOS

3. **Error Handling & Recovery**
   - Add comprehensive error handling
   - Implement data recovery mechanisms
   - Create debugging tools for sync issues

**Deliverables**: Production-ready unified clipboard sync system

## Technical Architecture

### New Components to Build

1. **DeviceManager**
   ```swift
   class DeviceManager {
       static let shared = DeviceManager()
       var deviceID: String { get }
       var deviceInfo: DeviceInfo { get }
   }
   ```

2. **ClipboardCorrelator**
   ```swift
   class ClipboardCorrelator {
       func correlateWithUniversalClipboard(content: String, timestamp: Date) -> CorrelationResult
       func findCanonicalID(for content: String) -> UUID?
   }
   ```

3. **IDResolver**
   ```swift
   class IDResolver {
       func resolveCanonicalID(for item: ClipboardItem) -> UUID
       func updateItemWithCanonicalID(_ item: ClipboardItem, canonicalID: UUID)
   }
   ```

### Data Flow Examples

**Scenario 1: Mac → iPhone**
1. User copies on Mac → `ClipboardMonitor` creates item with `canonicalID` = `abc-123`, `initiatingDevice` = `mac-device-id`
2. Universal Clipboard transfers to iPhone
3. iPhone `ClipboardService` detects paste → creates temporary item with `syncSource` = `universal_clipboard`
4. `ClipboardCorrelator` matches content/timing → identifies Mac as initiator
5. `IDResolver` updates iPhone item with `canonicalID` = `abc-123`
6. CloudKit syncs unified record

**Scenario 2: Delete from iPhone**
1. User deletes item with `canonicalID` = `abc-123` on iPhone
2. iPhone deletes local record and marks for CloudKit deletion
3. CloudKit propagates delete to Mac
4. Mac receives remote change notification → deletes local record with matching `canonicalID`

## Success Criteria

### Functional Requirements
- [ ] Same clipboard content has identical UUID across all devices
- [ ] Delete from any device removes from all devices within 30 seconds
- [ ] Edit from any device updates all devices within 30 seconds
- [ ] System works offline and syncs when connection restored
- [ ] No duplicate items created for Universal Clipboard transfers

### Performance Requirements
- [ ] Clipboard detection latency < 100ms on macOS
- [ ] Clipboard detection latency < 500ms on iOS
- [ ] ID resolution completes within 5 seconds
- [ ] Cross-device sync completes within 30 seconds
- [ ] No significant battery impact on iOS

### Reliability Requirements
- [ ] 99.9% accuracy in correlating Universal Clipboard transfers
- [ ] Zero data loss during ID resolution process
- [ ] Graceful handling of network interruptions
- [ ] Automatic recovery from sync conflicts

## Risk Mitigation

### High Risk Items
1. **Universal Clipboard Timing**: Apple's timing may be inconsistent
   - *Mitigation*: Use flexible timing windows, content-based fallback matching

2. **CloudKit Conflicts**: Simultaneous operations could create conflicts
   - *Mitigation*: Implement robust conflict resolution, use timestamps as tiebreakers

3. **Migration Issues**: Existing users have items with old schema
   - *Mitigation*: Thorough migration testing, fallback to current behavior for old items

### Medium Risk Items
1. **Performance Impact**: Additional processing could slow clipboard monitoring
   - *Mitigation*: Optimize algorithms, use background queues for heavy operations

2. **iOS Background Limitations**: iOS may limit background clipboard monitoring
   - *Mitigation*: Optimize for foreground sync, use push notifications where possible

## Testing Strategy

### Unit Tests
- Device identification and persistence
- Content correlation algorithms
- ID resolution logic
- CloudKit sync operations

### Integration Tests
- End-to-end copy/paste scenarios
- Multi-device delete/edit propagation
- Offline/online sync scenarios
- Migration from existing data

### Manual Testing
- Real-world usage across multiple devices
- Network interruption scenarios
- Performance testing with large clipboard histories
- User experience validation

## Success Metrics

- **Sync Accuracy**: 99.9% of Universal Clipboard transfers correctly unified
- **Sync Speed**: 95% of operations complete within target times
- **User Satisfaction**: No user reports of "duplicate" or "missing" clipboard items
- **System Stability**: No crashes or data corruption related to sync system

## Future Enhancements

- Real-time collaboration features
- Clipboard sharing with other users
- Advanced conflict resolution UI
- Clipboard analytics and insights
- Integration with other Apple ecosystem features 