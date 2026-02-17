# Victor TODO

Last updated: 2026-02-17
Migrated from beads issue tracker

## Epics

### Code Review 2026-01 - Quality & Security Improvements (P1)
**ID**: victor-oci
Comprehensive code review findings from expert panel covering security, architecture, SwiftUI best practices, and DRY principles.

**Scope**:
- 4 P0 Critical items (security hardening)
- 4 P1 High priority items (architecture, accessibility)
- 8 P2 Medium priority items (performance, DRY)
- 6 P3 Low priority items (nice to have)

**Reference**: See Docs/CODE-REVIEW-PLAN.md for full details

**Child Tasks**:
- victor-zw4: Add protocol abstractions for services (P2)
- And 26 other code review items tracked in CODE-REVIEW-PLAN.md

### File System Watching (FSEvents) for Auto-Reload (P3)
**ID**: victor-iv0
Implement file system watching to automatically reload files when changed externally.

**Implementation**:
- Use FSEvents API to watch Hugo site directory
- Detect file changes, additions, deletions
- Auto-reload affected files in editor
- Show notification when external changes detected
- Conflict resolution dialog if file modified in both places
- Preference to enable/disable auto-reload

**Files**: FileSystemWatcher.swift (new), SiteViewModel.swift, AutoSaveService.swift (modified)
**Estimated**: 3-4 hours

**Child Tasks** (all P2):
1. victor-bfs: Create FileWatcherService actor
2. victor-93p: Create FileChangeNotification model
3. victor-5cl: Add file watcher lifecycle to SiteViewModel
4. victor-so7: Add save intent registration to save operations
5. victor-rpt: Create notification UI views
6. victor-u5y: Integrate notifications into ContentView
7. victor-8cw: Add file watching preference toggle
8. victor-8u1: Handle edge cases (delete, rename, batch)
9. victor-rey: Add automated test coverage for file watcher

### Git Integration (P3)
**ID**: victor-edf
Add Git integration for viewing status and committing changes from within Victor.

**Implementation**:
- Git status display in sidebar (show modified/staged/untracked files)
- Commit dialog with message input and file staging
- Push/pull buttons in toolbar
- Branch display and switching
- Diff viewer for changed files
- Use libgit2 or shell out to git command

**Files**: GitService.swift, GitStatusView.swift, CommitDialog.swift (new)
**Estimated**: 5-6 hours

**Child Tasks** (all P3):
1. victor-04m: Create GitService for git operations
2. victor-cit: Git status display in sidebar (depends on victor-04m)
3. victor-7zv: Commit dialog with file staging (depends on victor-04m)
4. victor-agi: Push/Pull functionality (depends on victor-04m)
5. victor-95t: Branch display and switching (depends on victor-04m)
6. victor-2d4: Diff viewer for changed files (depends on victor-04m)

---

## File System Watching Tasks (P2)

### victor-bfs: Create FileWatcherService actor
Create new actor service at `Victor/Services/FileWatcherService.swift` managing FSEventStream lifecycle.

**Implementation Details**:
- Actor-based design following AutoSaveService pattern for thread safety
- FSEvents callbacks occur on arbitrary background threads, requiring actor isolation
- Use `FSEventStreamCreate` with flags: `kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer`
- Set dispatch queue to `DispatchQueue.global(qos: .utility)`

**Key Methods**:
- `startWatching(path:delegate:)` - Create and start FSEventStream
- `stopWatching()` - Stop, invalidate, and release stream
- `registerSaveIntent(for:)` - Mark URL as 'our save' to ignore (prevents false positives)

**Event Coalescing**:
- Accumulate events in 500ms window before processing
- Use `pendingEvents: [URL: FileChangeEvent]` dictionary
- Schedule coalescing with cancellable Task
- After window expires, batch events and notify delegate

**Save Intent Registry**:
- `saveIntents: [URL: Date]` dictionary tracks internal saves
- 5-second expiration for intent registration
- When FSEvent fires, check if URL in registry - if so, ignore and clear

**Types to Define**:
- `FileChangeEvent` enum: .modified, .created, .deleted, .renamed
- `FileChangeBatch` struct with events dictionary
- `FileWatcherDelegate` protocol with async callback

**Constants** (add to AppConstants.swift):
- `FileWatcher.coalesceWindow = 0.5`
- `FileWatcher.saveIntentTimeout = 5.0`
- `FileWatcher.fsEventsLatency = 0.3`

### victor-93p: Create FileChangeNotification model
**Depends on**: victor-iv0

Create model for UI notifications at `Victor/Models/FileChangeNotification.swift`.

**FileChangeNotification struct**:
```swift
struct FileChangeNotification: Identifiable {
    let id: UUID
    let type: NotificationType
    let urls: [URL]
    let message: String
    let timestamp: Date

    enum NotificationType {
        case conflict      // File changed externally AND locally
        case autoReloaded  // File auto-reloaded (no local changes)
        case deleted       // File was deleted externally
        case created       // New files detected
    }
}
```

**Usage**:
- Conflict: '${filename}' was modified. You have unsaved changes.
- Auto-reloaded: N file(s) reloaded from disk
- Deleted: '${filename}' was deleted externally
- Created: N new file(s) detected

**Action Options**:
- Reload from Disk
- Keep Editing (for conflicts)
- Dismiss
- Show All (for batch)

### victor-5cl: Add file watcher lifecycle to SiteViewModel
**Depends on**: victor-bfs, victor-93p

Integrate FileWatcherService lifecycle into SiteViewModel.

**New Properties**:
```swift
private var fileWatcher: FileWatcherService?
var fileChangeNotifications: [FileChangeNotification] = []
@AppStorage("isFileWatchingEnabled") var isFileWatchingEnabled = true
```

**New Methods**:
```swift
func startFileWatching() async {
    guard isFileWatchingEnabled, let siteURL = site?.rootURL else { return }
    fileWatcher = FileWatcherService()
    await fileWatcher?.startWatching(path: siteURL.path, delegate: self)
}

func stopFileWatching() {
    fileWatcher?.stopWatching()
    fileWatcher = nil
}
```

**Lifecycle Integration**:
- `loadSite(from:)` → call `startFileWatching()` after success
- `closeSite()` → call `stopFileWatching()` before clearing state
- `reloadSite()` → restart with stop then start

**Implement FileWatcherDelegate**:
```swift
extension SiteViewModel: FileWatcherDelegate {
    func fileWatcherDidDetectChanges(_ batch: FileChangeBatch) async {
        // Filter to site files only
        // Check modifiedFileIDs for conflicts
        // Auto-reload unmodified files if preference enabled
        // Create FileChangeNotification for conflicts
    }
}
```

**Notification Management**:
- `dismissNotification(_ notification:)`
- `reloadExternallyChangedFiles(_ notification:)`
- `scheduleNotificationDismissal(_ notification:)` with 5s timer

### victor-so7: Add save intent registration to save operations
**Depends on**: victor-bfs

Modify AutoSaveService and FileSystemService to register save intents before writes.

**Purpose**: Prevents FileWatcherService from treating our own saves as external changes. This avoids fragile timestamp comparison.

**AutoSaveService.swift modifications**:
In `performSave()` method, before the actual write:
```swift
await FileWatcherService.shared.registerSaveIntent(for: fileURL)
```

**FileSystemService.swift modifications**:
Add intent registration to:
1. `writeFile(to:content:)` - line ~281
2. `createFile(at:content:)` - line ~370
3. `duplicateFile(at:)` - line ~411

**Pattern**:
```swift
// Before NSFileCoordinator write:
await FileWatcherService.shared.registerSaveIntent(for: url)

let coordinator = NSFileCoordinator()
coordinator.coordinate(writingItemAt: url, ...) { ... }
```

**Timing**:
- Intent valid for 5 seconds (saveIntentTimeout)
- Covers slow saves and I/O delays
- Auto-expires to handle edge cases

### victor-rpt: Create notification UI views
**Depends on**: victor-93p

Create toast/banner UI for file change notifications.

**Files to Create**:

**1. Victor/Views/Notifications/FileChangeNotificationView.swift**
Single notification banner:
- Horizontal layout: icon + message + action buttons
- Icon based on notification type (exclamationmark.triangle, checkmark.circle, etc.)
- Action buttons: Reload / Dismiss (or Keep Editing for conflicts)
- Subtle background with rounded corners
- Animated appearance/disappearance

```swift
struct FileChangeNotificationView: View {
    let notification: FileChangeNotification
    let onDismiss: () -> Void
    let onReload: () -> Void

    var body: some View {
        HStack {
            Image(systemName: iconName)
            Text(notification.message)
            Spacer()
            Button("Reload") { onReload() }
            Button("Dismiss") { onDismiss() }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}
```

**2. Victor/Views/Notifications/FileChangeNotificationContainer.swift**
Container managing multiple notifications:
- VStack of notifications with spacing
- Animated entry/exit transitions
- Auto-dismiss timer (5 seconds)
- Maximum 3 visible notifications (queue extras)

**Styling**:
- Use semantic colors from Color+Semantic.swift
- Conflict: orange tint
- Auto-reloaded: green tint
- Deleted: red tint

### victor-u5y: Integrate notifications into ContentView
**Depends on**: victor-rpt, victor-5cl

Add notification overlay to main content area.

**ContentView.swift modification**:
Add overlay to the main content area (detail column):
```swift
.overlay(alignment: .top) {
    FileChangeNotificationContainer(
        notifications: siteViewModel.fileChangeNotifications,
        onDismiss: { siteViewModel.dismissNotification($0) },
        onReload: { Task { await siteViewModel.reloadExternallyChangedFiles($0) } }
    )
    .padding(.top, 8)
    .padding(.horizontal, 16)
}
```

**Positioning**:
- Top of editor area, below toolbar/tab bar
- Horizontally centered with padding
- Z-index above editor content

**Focus Mode Consideration**:
- Queue notifications during focus mode
- Display queued notifications when exiting focus mode
- Add check in FocusModeView or notification container

**App Termination**:
In VictorApp.swift, add cleanup:
```swift
func applicationWillTerminate(_ notification: Notification) {
    siteViewModel?.stopFileWatching()
}
```

### victor-8cw: Add file watching preference toggle
**Depends on**: victor-5cl

Add preference section to enable/disable file watching.

**PreferencesView.swift modification**:
Add new section:
```swift
Section {
    Toggle("Enable file watching", isOn: $isFileWatchingEnabled)
        .toggleStyle(.checkbox)

    if isFileWatchingEnabled {
        Toggle("Auto-reload unchanged files", isOn: $autoReloadUnchangedFiles)
            .toggleStyle(.checkbox)
            .padding(.leading, 20)
    }
} header: {
    Text("File Watching")
} footer: {
    Text("Detect when files are modified by external applications.")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

**AppStorage Keys** (add to AppConstants.swift):
```swift
enum UserDefaultsKeys {
    static let isFileWatchingEnabled = "isFileWatchingEnabled"
    static let autoReloadUnchangedFiles = "autoReloadUnchangedFiles"
}
```

**Behavior**:
- isFileWatchingEnabled: Master toggle, stops/starts FileWatcherService
- autoReloadUnchangedFiles: If true, silently reload files without local changes
- If false, show notification for all external changes

**SiteViewModel Integration**:
Watch for preference changes and restart watcher:
```swift
.onChange(of: isFileWatchingEnabled) { _, newValue in
    if newValue {
        Task { await startFileWatching() }
    } else {
        stopFileWatching()
    }
}
```

### victor-8u1: Handle edge cases (delete, rename, batch)
**Depends on**: victor-5cl

Handle edge cases in file watching.

**1. Deleted Files**:
- If currently editing deleted file: show alert with options
  - Save to New Location
  - Close Without Saving
- If file in sidebar but not open: mark as deleted or remove from tree
- Use FSEventStreamEventFlags: kFSEventStreamEventFlagItemRemoved

**2. Renamed/Moved Files**:
- FSEvents provides kFSEventStreamEventFlagItemRenamed
- Renamed events come in pairs (old path, new path)
- Update FileNode.url if file moved within site
- If currently open: update editor title/path

**3. New Files Created**:
- Detect via kFSEventStreamEventFlagItemCreated
- Trigger sidebar refresh for new files in watched directories
- Option: full reloadSite() or targeted folder refresh
- Show notification: 'N new file(s) detected'

**4. Batch Operations** (git checkout):
- FSEvents naturally batches events
- Coalesce window (500ms) groups rapid changes
- Show consolidated notification: '15 files changed externally'
- Action: 'Reload All' button reloads all affected files

**5. Directory Changes**:
- Folders deleted: remove from tree, close any open files from that folder
- Folders created: refresh parent to show new folder
- Use kFSEventStreamEventFlagItemIsDir to detect directories

**6. Focus Mode**:
- Queue notifications during focus mode
- Check focusModeEnabled in SiteViewModel before showing notifications
- Display queued notifications on focus mode exit

**7. App in Background**:
- FSEvents continues to fire while app inactive
- Process queued events when app becomes active
- Consider NSWorkspace.shared.notificationCenter for activation events

### victor-rey: Add automated test coverage for file watcher
**Depends on**: victor-u5y, victor-8cw, victor-8u1

Create comprehensive test coverage for FileWatcherService.

**New Test File**: Victor/Tests/FileWatcherServiceTests.swift

**1. Save Intent Registry Tests**:
- testRegisterSaveIntent_addsToRegistry
- testRegisterSaveIntent_expiresAfterTimeout
- testRegisterSaveIntent_clearedOnEventMatch
- testMultipleSaveIntents_trackedIndependently

**2. Event Coalescing Tests**:
- testCoalescing_batchesRapidEvents
- testCoalescing_respectsWindow
- testCoalescing_firesAfterQuietPeriod
- testCoalescing_cancelsPreviousTask

**3. Event Classification Tests**:
- testClassifyEvent_modified
- testClassifyEvent_created
- testClassifyEvent_deleted
- testClassifyEvent_renamed

**4. Delegate Callback Tests**:
- testDelegate_calledWithBatchedEvents
- testDelegate_notCalledForOwnSaves
- testDelegate_calledOnMainThread

**5. Lifecycle Tests**:
- testStartWatching_createsStream
- testStopWatching_releasesStream
- testStopWatching_clearsState
- testRestartWatching_worksCorrectly

**SiteViewModel Integration Tests** (FileWatcherIntegrationTests.swift):

**6. Conflict Detection Tests**:
- testExternalChange_withLocalChanges_showsConflict
- testExternalChange_withoutLocalChanges_autoReloads
- testConflictNotification_containsCorrectInfo

**7. Notification Management Tests**:
- testNotification_autoDismissesAfterTimeout
- testNotification_dismissedOnUserAction
- testMultipleNotifications_queuedCorrectly

**8. Preference Tests**:
- testWatchingDisabled_noEventsProcessed
- testAutoReloadDisabled_showsNotificationInstead
- testPreferenceChange_restartsWatcher

**Mock Strategy**:
- Create MockFileWatcherService for testing without real FSEvents
- Inject mock into SiteViewModel for integration tests
- Use protocol-based design for testability

---

## Git Integration Tasks (P3)

### victor-04m: Create GitService for git operations
Create a service layer for Git operations.

**Implementation**:
- Create GitService.swift
- Methods: status(), stage(), unstage(), commit(), push(), pull()
- Use Process to shell out to git command (simpler than libgit2)
- Handle errors gracefully

**File**: GitService.swift (new)

### victor-cit: Git status display in sidebar
**Depends on**: victor-04m

Show git status indicators in the file list sidebar.

**Implementation**:
- Show modified/staged/untracked file indicators
- Color-coded badges or icons
- Integration with SiteViewModel to track git status

**Files**: FileListView.swift, SiteViewModel.swift

### victor-7zv: Commit dialog with file staging
**Depends on**: victor-04m

Create commit dialog for staging and committing changes.

**Implementation**:
- CommitDialog.swift
- File list with checkboxes for staging
- Commit message text field
- Commit button with validation

**File**: CommitDialog.swift (new)

### victor-agi: Push/Pull functionality
**Depends on**: victor-04m

Add push and pull buttons to toolbar.

**Implementation**:
- Add push/pull buttons to toolbar
- Show progress indicators
- Handle auth (SSH keys or credential helper)
- Error handling for conflicts

**Files**: Toolbar view, GitService.swift

### victor-95t: Branch display and switching
**Depends on**: victor-04m

Show current branch and allow switching.

**Implementation**:
- Display current branch name in UI
- Branch picker/dropdown
- Create new branch option
- Handle uncommitted changes on switch

**Files**: GitStatusView.swift (new), GitService.swift

### victor-2d4: Diff viewer for changed files
**Depends on**: victor-04m

Show diffs for changed files.

**Implementation**:
- DiffViewer.swift
- Side-by-side or inline diff view
- Syntax highlighting for diff
- Navigate between changed hunks

**File**: DiffViewer.swift (new)

---

## Architecture Tasks (P2)

### victor-zw4: ARCH-2: Add protocol abstractions for services
**Files**: All service files (FileSystemService, HugoServerService, AutoSaveService, etc.)

**Issue**: Services are concrete classes without protocol abstractions. 212 instances of .shared across 41 files. Hard to test, creates tight coupling.

**Fix**: Create protocol abstractions:

```swift
protocol FileSystemServicing {
    func readContentFile(at url: URL) async throws -> ContentFile
    func writeContentFile(_ content: String, to url: URL) async throws
    // ... other methods
}

final class FileSystemService: FileSystemServicing {
    static let shared: FileSystemServicing = FileSystemService()
    // ... implementation
}
```

Then inject via constructor or SwiftUI Environment:
```swift
@Environment(\.fileSystemService) var fileSystemService
```

**Effort**: Medium (2 days)

**Reference**: Docs/CODE-REVIEW-PLAN.md ARCH-2

---

## Other Features (P3)

### victor-ayz: GH#1: Load CSS from Hugo theme for realistic preview
Feature: Load CSS from Hugo theme so preview matches final published output.

**Implementation considerations**:
- Detect theme configured in hugo.toml/config.toml
- Parse theme's CSS files (may need SCSS/Sass compilation)
- Handle themes with multiple CSS files or build systems
- Cache compiled CSS for performance
- Fallback to built-in styles if theme CSS unavailable

**Acceptance criteria**:
- Preview styling matches Hugo theme output
- Fallback to default styles when theme CSS unavailable
- No significant performance impact on preview updates

**Files**: Victor/Services/MarkdownRenderer.swift (wrapInHTMLTemplate method)

**GitHub Issue**: https://github.com/karanj/victor/issues/1

**Note**: Implementation attempt findings (2026-01-13) - Direct CSS loading doesn't work for most themes. Most themes use SCSS/Sass in assets/scss/ which requires Hugo's Sass compiler. Theme CSS depends on Hugo's template output. The only practical way to get theme-accurate previews is Hugo Server Integration (see comments in beads issue for details).

### victor-1o0: Syntax highlighting for code blocks in markdown preview
Add syntax highlighting for code blocks in the markdown preview panel.

**Implementation**:
- Integrate highlight.js or Prism.js into preview WebView
- Support common languages (Swift, JavaScript, Python, Go, etc.)
- Auto-detect language from fence info string
- Theme selection (light/dark mode support)
- Line numbers option

**Files**: PreviewWebView.swift, MarkdownRenderer.swift (modified)
**Estimated**: 2-3 hours

---

## Accessibility (P4)

### victor-3l6: VoiceOver improvements for accessibility
Improve VoiceOver support and accessibility throughout the app.

**Implementation**:
- Add proper accessibility labels to all buttons and controls
- Improve navigation hints for complex views
- Add accessibility traits to custom views
- Keyboard navigation improvements
- Screen reader announcements for important state changes
- Test with VoiceOver enabled
- Follow Apple Accessibility Guidelines

**Files**: All views (accessibilityLabel, accessibilityHint, accessibilityTraits)
**Estimated**: 3-4 hours

---

## Notes

- **Priority Legend**: P0 (Critical) → P1 (High) → P2 (Medium) → P3 (Low) → P4 (Backlog)
- Tasks are organized by epic/feature area
- Dependencies noted where applicable
- Estimated effort included where available
- See Docs/CODE-REVIEW-PLAN.md for additional code review items tracked under victor-oci epic
