# Critical Code Analysis — 2026-07-03

Full-codebase critical pass after a long gap, ahead of the "Mac-assed Mac app"
polish effort. Focus: concurrency-sensitive code (ViewModels, actors, process
management), save/data-integrity paths, and preference wiring. Baseline before
changes: clean build, all tests passing.

All fixes below were done test-first: each behavioral fix has a test that was
confirmed failing (red) on the old code and passing after the fix.

## Fixed in this session

### 1. Data loss in Save All / Save-and-Quit (SiteViewModel.saveAllModifiedFiles)
Unsaved edits live in `FileCacheManager` (per-file cache); `contentFile.markdownContent`
only updates on explicit save. Save All wrote `contentFile.fullContent`, i.e. the
*stale loaded* content. Quitting via "Save and Quit" silently discarded edits.
**Fix:** sync the cached edited content onto `contentFile` before writing.
**Test:** `SiteViewModelTests.testSaveAllModifiedFilesWritesEditedContentNotStaleContent`.

### 2. Main-thread infinite loop in LRU eviction (SiteViewModel.updateContentCache)
The eviction loop popped the last (oldest) entry and, if it was protected
(selected/modified), re-inserted it at the *end* — popping the same entry
forever. Triggered once >50 files are cached and the oldest is protected:
hard app hang. `FileCacheManager.evictIfNeeded` had the same non-termination
when *all* entries are protected (rotation never converges).
**Fix:** both now do a single reverse pass collecting evictable candidates —
termination is guaranteed by construction.
**Test:** `FileCacheManagerTests.testEvictIfNeededTerminatesWhenAllEntriesProtected`
(this test hangs on the old code; excluded from the red run for that reason).

### 3. findNode(id:) missed nodes created after site load
`nodeByID` is only built during `loadSite`. Files created via New File /
Duplicate / New Folder were never registered, so `findNode(id:)` returned nil
for them — meaning `saveAllModifiedFiles` and `isFileModified` silently
skipped newly created files.
**Fix:** `findNode(id:)` falls back to tree traversal (and memoizes);
mutation paths (`createMarkdownFile`, `duplicateFile`, `createFolder`,
`moveToTrash`, `closeSite`) now register/unregister in the lookup table.
**Test:** `SiteViewModelTests.testFindNodeByID` (updated: previously asserted
the broken behavior as "current behavior").

### 4. Cross-file auto-save cancellation (AutoSaveService)
One global `saveTask` meant scheduling a save for file B cancelled file A's
pending debounced save. Edit A → switch to B and type within the debounce
window → A's save never hit disk.
**Fix:** per-URL task dictionary with generation tokens for cleanup;
`cancelAutoSave()` cancels all, `cancelAutoSave(for:)` cancels one.
**Test:** `AutoSaveServiceTests.testSchedulingSecondFileDoesNotCancelFirstFilesPendingSave`.

### 5. autoSaveDelay preference ignored (AutoSaveService)
Preferences exposes "Save after: 1/2/3/5/10 seconds" and persists it, but the
service used a hard-coded 2.0s.
**Fix:** debounce interval reads the `autoSaveDelay` key, falling back to the
constant. (`TextEditorViewModel` already honored it; now both paths do.)
**Test:** `AutoSaveServiceTests.testAutoSaveHonorsDelayPreference`.

### 6. Auto-save enabled default was incoherent (5 readers, 2 defaults)
`SiteViewModel` defaulted the `isAutoSaveEnabled` key to **true** (and the
existing test asserts true is intended); `VictorApp` menu toggle,
`PreferencesView`, `EditorViewModel`, and `TextEditorViewModel` all defaulted
**false**, three of them via raw string keys. On a fresh install the UI said
auto-save was on but nothing ever auto-saved.
**Fix:** single source of truth `AppConstants.AutoSave.defaultEnabled = true`,
all readers use `AppConstants.UserDefaultsKeys` and the shared default.

### 7. Preferences "Server Defaults" were dead settings
`hugoServerPort` / `hugoServerBuildDrafts` / `hugoServerBuildFuture` /
`hugoServerBuildExpired` were written by PreferencesView but never read.
**Fix:** `HugoServerConfig.fromUserDefaults()` seeds `HugoServerService`'s
initial config (only keys the user actually set override built-ins; port is
range-validated). PreferencesView's displayed defaults now match the struct's
real defaults (drafts/future on, expired off). The per-session
ServerConfigPopover still overrides in memory, as before.

### 8. Path traversal boundary bug (FileSystemService.validatePathWithinSite)
`hasPrefix` on raw paths accepted sibling directories sharing a name prefix:
`/sites/blog-evil` validated against root `/sites/blog`. Also, relative
symlink destinations were resolved as if absolute.
**Fix:** directory-boundary-aware containment check (`root + "/"` or exact
match); symlink destinations resolved relative to the link's directory.
**Test:** `FileOperationsServiceTests.testValidatePathRejectsSiblingDirectoryWithRootPrefix`.

### 9. Hugo server shutdown hygiene (HugoServerService)
"Force kill" after SIGTERM used `process.interrupt()` (SIGINT — weaker than
the SIGTERM already sent); pipe `readabilityHandler`s were never cleared on
stop/termination, retaining file handles and firing stray reads.
**Fix:** SIGKILL for the force path; handlers cleared in both `stop()` and
`handleProcessTermination`.

### 10. LiveReloadClient leaked a URLSession per reconnect attempt
`establishConnection()` created a fresh URLSession (which strongly retains its
delegate) on every 2s retry without invalidating the previous one.
**Fix:** cancel the old task and `invalidateAndCancel()` the old session at
the top of `establishConnection()`.

## Deliberately not changed

- `EditorViewModel.cleanup()` intentionally does not cancel pending auto-saves
  on file switch (content is captured at schedule time; save completes
  correctly in the background). With per-file tasks (#4) this design is now
  actually sound — previously the next file's schedule cancelled it anyway.
- Non-atomic file writes remain intentional (Hugo's watcher needs the inode
  to survive for `--navigateToChanged`); documented in code.

## Outstanding (filed in ISSUES.yaml, Code Health section)

- `victor-u16` (P3): UTF-16 vs grapheme `.count` mismatches across
  EditorTextView (cursor/selection wrong with emoji), plus stale
  `Coordinator.parent` in `updateNSView`.
- `victor-lru` (P3): `FileCacheManager.evictIfNeeded`/`onEviction` are never
  called — edited-content cache is unbounded; two parallel LRU mechanisms
  should be consolidated.
- `victor-rbo` (P4): LiveReload reconnect retries forever with no backoff.
- `victor-prt` (P4): port probe lacks SO_REUSEADDR → TIME_WAIT ports read as
  busy and the server drifts to port+1.
- `victor-ilf` (P4): `isLoadingFile` resets race across rapid file switches.
- Pre-existing `victor-stn` (settings service) is the right home for the
  remaining UserDefaults-vs-@AppStorage duplication (e.g.
  `SiteViewModel.isAutoSaveEnabled` doesn't observe external toggles).

## Verification

- `xcodebuild test` — full suite green after changes (was green before; 5 new
  tests added, 1 rewritten; all new tests confirmed red on the old code).
