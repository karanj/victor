# Victor TODO

Last updated: 2026-02-17

## Format

Each ticket uses the following DSL:

```
### [ID] Title
- **Status**: open | in-progress | blocked | done
- **Priority**: P0 (critical) | P1 (high) | P2 (medium) | P3 (low) | P4 (backlog)
- **Type**: epic | task | feature | bug
- **Blocked by**: [ticket IDs this depends on]
- **Blocks**: [ticket IDs that depend on this]
- **Files**: [files to create or modify]
- **Estimate**: [time estimate if known]

Description and implementation details.
```

---

## Summary

| Priority | Open | Done | Total |
|----------|------|------|-------|
| P0       | 0    | 4    | 4     |
| P1       | 0    | 7    | 7     |
| P2       | 10   | 8    | 18    |
| P3       | 7    | 19   | 26    |
| P4       | 1    | 0    | 1     |
| **Total**| **18** | **38** | **56** |

---

## Open Tickets

### Architecture

#### [victor-zw4] ARCH-2: Add protocol abstractions for services
- **Status**: open
- **Priority**: P2
- **Type**: task
- **Blocked by**: none
- **Files**: All service files (FileSystemService, HugoServerService, AutoSaveService, AssetService, SearchService, etc.)
- **Estimate**: 2 days
- **Review ref**: CODE-REVIEW-PLAN.md ARCH-2

Services use concrete `.shared` singletons (212 instances across 41 files). Hard to test, creates tight coupling.

**Fix**: Create protocol abstractions and inject via constructor or SwiftUI Environment:
```swift
protocol FileSystemServicing {
    func readContentFile(at url: URL) async throws -> ContentFile
    func writeContentFile(_ content: String, to url: URL) async throws
}

@Environment(\.fileSystemService) var fileSystemService
```

---

### File System Watching (FSEvents)

Epic: **victor-iv0** — Auto-reload files when changed externally. Uses FSEvents API for directory watching with event coalescing, save intent registry (to ignore our own writes), and toast notifications for conflicts.

#### [victor-bfs] Create FileWatcherService actor
- **Status**: open
- **Priority**: P2
- **Type**: task
- **Blocked by**: none (entry point for FSEvents work)
- **Blocks**: victor-5cl, victor-so7
- **Files**: `Victor/Services/FileWatcherService.swift` (new), `Victor/AppConstants.swift`
- **Estimate**: 2-3 hours

Create actor-based service managing FSEventStream lifecycle, following AutoSaveService pattern.

**Key design**:
- `startWatching(path:delegate:)` / `stopWatching()` for stream lifecycle
- `registerSaveIntent(for:)` — marks URL as internal save to ignore (5s expiry)
- Event coalescing: accumulate in 500ms window via `pendingEvents: [URL: FileChangeEvent]`
- FSEvents flags: `kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer`
- Dispatch to `DispatchQueue.global(qos: .utility)`

**Types to define**: `FileChangeEvent` (.modified/.created/.deleted/.renamed), `FileChangeBatch`, `FileWatcherDelegate` protocol.

**Constants** for AppConstants: `FileWatcher.coalesceWindow = 0.5`, `FileWatcher.saveIntentTimeout = 5.0`, `FileWatcher.fsEventsLatency = 0.3`

#### [victor-93p] Create FileChangeNotification model
- **Status**: open
- **Priority**: P2
- **Type**: task
- **Blocked by**: none
- **Blocks**: victor-rpt, victor-5cl
- **Files**: `Victor/Models/FileChangeNotification.swift` (new)
- **Estimate**: 30 min

```swift
struct FileChangeNotification: Identifiable {
    let id: UUID
    let type: NotificationType  // .conflict, .autoReloaded, .deleted, .created
    let urls: [URL]
    let message: String
    let timestamp: Date
}
```

Action options: Reload from Disk, Keep Editing (conflicts), Dismiss, Show All (batch).

#### [victor-5cl] Add file watcher lifecycle to SiteViewModel
- **Status**: open
- **Priority**: P2
- **Type**: task
- **Blocked by**: victor-bfs, victor-93p
- **Blocks**: victor-u5y, victor-8cw, victor-8u1
- **Files**: `Victor/ViewModels/SiteViewModel.swift`
- **Estimate**: 2-3 hours

Wire FileWatcherService into SiteViewModel lifecycle:
- `loadSite()` -> `startFileWatching()`
- `closeSite()` -> `stopFileWatching()`
- Implement `FileWatcherDelegate` to filter events, detect conflicts (check `editedContentByFile`), auto-reload unmodified files
- Manage `fileChangeNotifications` array with auto-dismiss timers

#### [victor-so7] Add save intent registration to save operations
- **Status**: open
- **Priority**: P2
- **Type**: task
- **Blocked by**: victor-bfs
- **Files**: `Victor/Services/AutoSaveService.swift`, `Victor/Services/FileSystemService.swift`
- **Estimate**: 1 hour

Call `FileWatcherService.shared.registerSaveIntent(for: url)` before every write in:
1. `AutoSaveService.performSave()`
2. `FileSystemService.writeFile(to:content:)`
3. `FileSystemService.createFile(at:content:)`
4. `FileSystemService.duplicateFile(at:)`

Prevents FSEvents from treating our own saves as external changes.

#### [victor-rpt] Create notification UI views
- **Status**: open
- **Priority**: P2
- **Type**: task
- **Blocked by**: victor-93p
- **Blocks**: victor-u5y
- **Files**: `Victor/Views/Notifications/FileChangeNotificationView.swift` (new), `Victor/Views/Notifications/FileChangeNotificationContainer.swift` (new)
- **Estimate**: 2 hours

Toast/banner UI:
- `FileChangeNotificationView`: icon + message + action buttons (Reload/Dismiss), `.ultraThinMaterial` background
- `FileChangeNotificationContainer`: VStack managing up to 3 visible notifications with animated entry/exit, 5s auto-dismiss
- Color tinting: orange (conflict), green (auto-reloaded), red (deleted)

#### [victor-u5y] Integrate notifications into ContentView
- **Status**: open
- **Priority**: P2
- **Type**: task
- **Blocked by**: victor-rpt, victor-5cl
- **Files**: `Victor/Views/MainWindow/ContentView.swift`, `Victor/VictorApp.swift`
- **Estimate**: 1 hour

Add `.overlay(alignment: .top)` with `FileChangeNotificationContainer` to main content area. Queue notifications during focus mode. Add `stopFileWatching()` cleanup in `applicationWillTerminate`.

#### [victor-8cw] Add file watching preference toggle
- **Status**: open
- **Priority**: P2
- **Type**: task
- **Blocked by**: victor-5cl
- **Files**: `Victor/Views/PreferencesView.swift`, `Victor/AppConstants.swift`
- **Estimate**: 30 min

Add "File Watching" section to PreferencesView with two toggles:
1. `isFileWatchingEnabled` — master toggle, starts/stops FileWatcherService
2. `autoReloadUnchangedFiles` — if true, silently reload; if false, show notification for all changes

#### [victor-8u1] Handle file watcher edge cases
- **Status**: open
- **Priority**: P2
- **Type**: task
- **Blocked by**: victor-5cl
- **Files**: `Victor/ViewModels/SiteViewModel.swift`, `Victor/Services/FileWatcherService.swift`
- **Estimate**: 3-4 hours

Edge cases to handle:
1. **Deleted files**: alert with Save to New Location / Close Without Saving
2. **Renamed files**: FSEvents renamed pairs, update FileNode.url
3. **New files**: trigger sidebar refresh, "N new file(s) detected" notification
4. **Batch operations** (git checkout): coalesce into single "15 files changed" notification with Reload All
5. **Directory changes**: remove deleted folders from tree, refresh for new folders
6. **Focus mode**: queue notifications, display on exit
7. **App in background**: process queued events on activation

#### [victor-rey] Add test coverage for file watcher
- **Status**: open
- **Priority**: P2
- **Type**: task
- **Blocked by**: victor-u5y, victor-8cw, victor-8u1
- **Files**: `VictorTests/FileWatcherServiceTests.swift` (new), `VictorTests/FileWatcherIntegrationTests.swift` (new)
- **Estimate**: 3-4 hours

Test categories:
- Save intent registry (add, expire, clear on match)
- Event coalescing (batch, window, quiet period, cancel)
- Event classification (modified, created, deleted, renamed)
- Delegate callbacks (batched events, skip own saves, main thread)
- Lifecycle (create stream, release, clear state, restart)
- Conflict detection (external + local changes, auto-reload)
- Notification management (auto-dismiss, user action, queue)
- Preferences (disabled = no events, auto-reload toggle, restart on change)

Uses `MockFileWatcherService` injected via protocol.

---

### Git Integration

Epic: **victor-edf** — View git status and commit changes from within Victor. P3 feature set, all tasks depend on victor-04m (GitService).

#### [victor-04m] Create GitService for git operations
- **Status**: open
- **Priority**: P3
- **Type**: task
- **Blocked by**: none (entry point for git work)
- **Blocks**: victor-cit, victor-7zv, victor-agi, victor-95t, victor-2d4
- **Files**: `Victor/Services/GitService.swift` (new)
- **Estimate**: 2-3 hours

Service layer using `Process` to shell out to git:
- `status()` -> parsed file statuses (modified, staged, untracked)
- `stage(_ files:)`, `unstage(_ files:)`
- `commit(message:)`, `push()`, `pull()`
- Error handling for missing git, not a repo, conflicts

#### [victor-cit] Git status display in sidebar
- **Status**: open
- **Priority**: P3
- **Type**: task
- **Blocked by**: victor-04m
- **Files**: `Victor/Views/MainWindow/FileListView.swift`, `Victor/ViewModels/SiteViewModel.swift`
- **Estimate**: 2 hours

Show color-coded badges/icons for modified, staged, untracked files in sidebar.

#### [victor-7zv] Commit dialog with file staging
- **Status**: open
- **Priority**: P3
- **Type**: task
- **Blocked by**: victor-04m
- **Files**: `Victor/Views/Git/CommitDialog.swift` (new)
- **Estimate**: 2-3 hours

File list with checkboxes for staging, commit message field, validation.

#### [victor-agi] Push/Pull functionality
- **Status**: open
- **Priority**: P3
- **Type**: feature
- **Blocked by**: victor-04m
- **Files**: Toolbar view, `Victor/Services/GitService.swift`
- **Estimate**: 2 hours

Push/pull toolbar buttons with progress indicators. Handle SSH keys / credential helper. Error handling for conflicts.

#### [victor-95t] Branch display and switching
- **Status**: open
- **Priority**: P3
- **Type**: task
- **Blocked by**: victor-04m
- **Files**: `Victor/Views/Git/GitStatusView.swift` (new), `Victor/Services/GitService.swift`
- **Estimate**: 2 hours

Current branch name display, branch picker/dropdown, create new branch, handle uncommitted changes on switch.

#### [victor-2d4] Diff viewer for changed files
- **Status**: open
- **Priority**: P3
- **Type**: task
- **Blocked by**: victor-04m
- **Files**: `Victor/Views/Git/DiffViewer.swift` (new)
- **Estimate**: 3-4 hours

Side-by-side or inline diff view with syntax highlighting and hunk navigation.

---

### Preview Enhancements

#### [victor-1o0] Syntax highlighting for code blocks in preview
- **Status**: open
- **Priority**: P3
- **Type**: task
- **Blocked by**: none
- **Files**: `Victor/Views/Preview/PreviewWebView.swift`, `Victor/Services/MarkdownRenderer.swift`
- **Estimate**: 2-3 hours

Integrate highlight.js or Prism.js into preview WebView. Support common languages (Swift, JS, Python, Go, etc.), auto-detect from fence info string, light/dark theme, optional line numbers.

#### [victor-ayz] GH#1: Load CSS from Hugo theme for preview
- **Status**: open
- **Priority**: P3
- **Type**: feature
- **Blocked by**: none
- **Files**: `Victor/Services/MarkdownRenderer.swift`
- **GitHub**: https://github.com/karanj/victor/issues/1

Load Hugo theme CSS so preview matches published output. Fallback to built-in styles when unavailable.

**Known blocker** (2026-01-13): Direct CSS loading doesn't work for most themes. Themes use SCSS/Sass in `assets/scss/` requiring Hugo's Sass compiler. Theme CSS depends on Hugo's template output. Only practical approach is piping through Hugo Server Integration.

---

### Accessibility

#### [victor-3l6] VoiceOver improvements
- **Status**: open
- **Priority**: P4
- **Type**: task
- **Blocked by**: none
- **Files**: All view files
- **Estimate**: 3-4 hours

Add accessibility labels/hints to all buttons and controls, improve navigation hints for complex views, add accessibility traits to custom views, keyboard navigation improvements, screen reader announcements for state changes. Test with VoiceOver enabled.

Note: Icon-only buttons already have labels (victor-0qe, done). This covers the remaining audit.

---

## Done Tickets

### Code Review 2026-01 (victor-oci) — All Complete Except ARCH-2

| ID | Title | Priority | Closed |
|----|-------|----------|--------|
| victor-cz6 | SEC-1: Validate Hugo binary path locations | P0 | 2026-01-19 |
| victor-0d0 | SEC-2: Path traversal protection | P0 | 2026-01-19 |
| victor-rbe | SEC-3: Content Security Policy for preview WebView | P0 | 2026-01-19 |
| victor-45w | ARCH-6: Log successful saves after file switch | P0 | 2026-01-19 |
| victor-ynu | UI-1: Extract ConfigEditor tabs to separate files | P1 | 2026-01-19 |
| victor-8ad | DRY-1: EmptyStateView + LoadingStateView + ErrorStateView | P1 | 2026-02-17 |
| victor-v51 | DRY-4: Extract parser helpers (TOMLHelper, SerializationHelper) | P1 | 2026-01-19 |
| victor-6r6 | ARCH-1: Extract SiteViewModel (FileCacheManager, FileOperationsService, SpecializedFileManager) | P1 | 2026-01-22 |
| victor-0qe | UI-4: Accessibility labels on icon-only buttons | P1 | 2026-01-19 |
| victor-5ng | UI-2: .equatable() on FileListView rows | P2 | 2026-01-22 |
| victor-669 | UI-3: Optimize AssetBrowserView filtering | P2 | 2026-01-22 |
| victor-5zp | ARCH-3: Evaluate struct vs class for models (kept classes, documented) | P2 | 2026-01-22 |
| victor-d4p | UI-5: Adjust GlobalSearch debounce timing | P2 | done |
| victor-jlc | DRY-2: BadgeStyle view modifier | P2 | done |
| victor-l85 | DRY-3: FormSectionView component | P2 | done |
| victor-hal | DRY-5: FileStatusBadgeView component | P2 | done |
| victor-rc5 | MN-1: Centralize remaining magic numbers | P2 | done |
| victor-2vp | DRY-6: LabeledTextField component | P3 | 2026-01-22 |
| victor-23p | DRY-7: SF Symbols constants enum | P3 | 2026-01-22 |
| victor-2ce | DRY-8: Text style view modifiers | P3 | 2026-01-22 |
| victor-41z | ARCH-5: Document state duplication rationale | P3 | 2026-01-22 |
| victor-mdk | ARCH-4: Document service actor strategy | P3 | done |
| victor-bmr | SEC-4: Certificate validation for WebSocket | P3 | done |
| victor-byt | SEC-5: Consider App Sandbox | P3 | done |
| victor-d75 | UI-6: Missing preview providers | P3 | done |
| victor-y1i | UI-7: Semantic font sizes | P3 | done |

### Other Completed Work

| ID | Title | Closed |
|----|-------|--------|
| victor-00z | Editor typing lag (5 optimizations) | 2026-01-14 |
| victor-1z5 | Flash of default content when switching files | 2026-01-12 |
| victor-1z2 | Hugo server warning vs error badge colors | 2026-01-16 |
| victor-0fm | Build error popover inconsistency in Live Preview | 2026-01-18 |
| victor-4wa | App crash on adding tab (disabled native tabbing) | 2026-01-08 |
| victor-27m | Inspector "no content selected" auto-hide | 2026-01-12 |
| victor-8u2 | Multi-file search & replace | 2026-01-13 |
| victor-42t | [EPIC] Phase 8: Hugo Server Integration | 2026-01-13 |
| victor-4kf | [EPIC] Phase 7: Template Editing | 2026-01-10 |
| victor-22v | ARCH-1.2: Extract FileOperationsService | 2026-01-20 |
| victor-49i | ARCH-1.1: Extract FileCacheManager | 2026-01-20 |

---

## Reference

- **Detailed code review findings**: `Docs/CODE-REVIEW-PLAN.md`
- **Priority legend**: P0 (critical) > P1 (high) > P2 (medium) > P3 (low) > P4 (backlog)
- **Dependency graph**: FSEvents chain is `bfs + 93p -> 5cl -> (u5y + 8cw + 8u1) -> rey`. Git chain is `04m -> (cit + 7zv + agi + 95t + 2d4)`.
- **Original issue tracker**: `.beads/issues.jsonl` (archived, no longer updated)
