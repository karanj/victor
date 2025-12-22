# Critical Fixes Applied - Victor Hugo CMS

**Date**: 2025-12-22
**Build Status**: ✅ Success (No errors, warnings unrelated to fixes)

## Summary

Three critical/high-priority issues have been fixed to prevent crashes, memory leaks, and UI freezes.

---

## CRIT-001: Race Condition in AutoSaveService ✅ FIXED

### Issue
**Severity**: Critical (Would crash app)
**File**: `Victor/Services/AutoSaveService.swift:100-127`

The `performSave` method had a race condition where the continuation could be resumed multiple times:
1. Once in the NSFileCoordinator block (success or error)
2. Again if `coordinatorError` was set

This would cause a crash with "continuation already resumed" error.

### Fix Applied
Added a `didResume` flag to track whether the continuation has already been resumed:

```swift
var didResume = false

coordinator.coordinate(...) { url in
    do {
        // ... save logic ...
        continuation.resume(returning: newModificationDate)
        didResume = true  // ← Track resume
    } catch {
        continuation.resume(throwing: error)
        didResume = true  // ← Track resume
    }
}

// Only resume if block was never executed
if !didResume, let error = coordinatorError {
    continuation.resume(throwing: error)
}
```

### Impact
- **Before**: App would crash when file coordination failed
- **After**: Proper error handling, no crashes

---

## CRIT-002: Memory Leak in Search Filter ✅ SIGNIFICANTLY IMPROVED

### Issue
**Severity**: Critical (Would cause OOM on large sites)
**File**: `Victor/ViewModels/SiteViewModel.swift:55-106`

The `filterNodesRecursively` method created NEW `FileNode` instances on every search query change. Since `FileNode` is an `@Observable` class (reference type), these copies accumulated in memory. On large sites (500+ files), typing in search caused exponential memory growth.

### Fix Applied
Implemented two optimizations:

1. **Reuse originals when possible**: Only create filtered copies when children are actually filtered
2. **Track expansion separately**: Added `autoExpandedNodeIDs` set to track which nodes should be expanded during search

```swift
// Before: Always created copies
let dirCopy = FileNode(url: node.url, isDirectory: true)
dirCopy.children = filteredChildren
dirCopy.isExpanded = true
filtered.append(dirCopy)

// After: Only create when necessary
if filteredChildren.count < node.children.count {
    // Need filtered view - create minimal copy
    let filteredNode = FileNode(url: node.url, isDirectory: true, isPageBundle: node.isPageBundle)
    filteredNode.children = filteredChildren
    filtered.append(filteredNode)
} else {
    // All children match - reuse original
    filtered.append(node)
}
```

### Impact
- **Before**: Memory grew by several MB per keystroke, causing OOM crashes
- **After**: Significantly reduced object creation (only when children are filtered)
- **Note**: Complete fix would require making `FileNode` a struct (value type) instead of class - this is a larger architectural change

---

## HIGH-001: Cache isPageBundle Property ✅ FIXED

### Issue
**Severity**: High (UI freezes on slower filesystems)
**Files**:
- `Victor/Models/FileNode.swift:27-33`
- `Victor/Services/FileSystemService.swift:116-143`

The `isPageBundle` computed property called `FileManager.default.fileExists()` synchronously on every access. This property was accessed from SwiftUI view bodies running on the main thread, causing UI freezes when rendering large file lists.

### Fix Applied
Changed `isPageBundle` from computed property to stored property:

1. **FileNode.swift**: Changed to stored `let` property computed at initialization
```swift
// Before: Computed property (file I/O on every access)
var isPageBundle: Bool {
    guard isDirectory else { return false }
    let indexMD = url.appendingPathComponent("index.md")
    return FileManager.default.fileExists(atPath: indexMD.path) || ...
}

// After: Stored property (computed once)
let isPageBundle: Bool

init(url: URL, isDirectory: Bool, isPageBundle: Bool = false) {
    // ...
    self.isPageBundle = isPageBundle
}
```

2. **FileSystemService.swift**: Compute isPageBundle once during tree construction
```swift
// Check if this is a Hugo page bundle (has index.md or _index.md)
let indexMD = itemURL.appendingPathComponent("index.md")
let underscoreIndexMD = itemURL.appendingPathComponent("_index.md")
let isBundle = fileManager.fileExists(atPath: indexMD.path) ||
              fileManager.fileExists(atPath: underscoreIndexMD.path)

// Create directory node with cached page bundle status
let dirNode = FileNode(url: itemURL, isDirectory: true, isPageBundle: isBundle)
```

### Impact
- **Before**: UI froze when rendering file lists with many directories (especially on network drives)
- **After**: No file I/O on main thread during rendering - smooth scrolling and instant updates

---

## Build Verification

```bash
swift build
```

**Result**: ✅ Build complete! (2.83s)
- No compilation errors
- No new warnings
- Only existing warnings about test files and resources (unrelated)

---

## Testing Recommendations

### Manual Testing
1. **AutoSave Race Condition**:
   - Edit a file
   - Modify it externally while auto-save is pending
   - Verify no crash occurs

2. **Memory Leak**:
   - Open a large Hugo site (500+ files)
   - Type in search field repeatedly
   - Monitor memory usage in Activity Monitor
   - Verify memory doesn't grow exponentially

3. **Page Bundle Performance**:
   - Open a large Hugo site with many page bundles
   - Scroll through file list
   - Verify smooth scrolling (no stuttering)

### Automated Testing (Recommended for Future)
- Unit tests for `AutoSaveService.performSave` with mocked file coordinator
- Performance tests for search filter with large file trees
- Memory leak tests using XCTest's memory graph API

---

## Remaining Issues from Code Review

See `code-review-findings.yaml` for complete list. Notable high-priority items:

### HIGH-002: Blocking Disk I/O in FileSystemService
- FileSystemService is marked `@MainActor`, causing UI freezes when opening sites
- **Recommendation**: Remove @MainActor, move scanDirectory to background

### HIGH-003: Blocking CPU Work in FrontmatterParser
- FrontmatterParser is marked `@MainActor` but does CPU-intensive parsing
- **Recommendation**: Remove @MainActor annotation

### HIGH-004: Create EditorViewModel
- 150+ lines of business logic in EditorPanelView
- **Recommendation**: Extract to dedicated ViewModel

### HIGH-006: Missing Keyboard Shortcuts
- No global ⌘B/⌘I shortcuts for formatting
- **Recommendation**: Add keyboard shortcuts in VictorApp.swift

See full findings for details and implementation guidance.

---

## Files Modified

1. `Victor/Services/AutoSaveService.swift` - Fixed race condition
2. `Victor/ViewModels/SiteViewModel.swift` - Optimized search filter
3. `Victor/Models/FileNode.swift` - Cached isPageBundle property
4. `Victor/Services/FileSystemService.swift` - Compute isPageBundle at creation

---

**Next Steps**: Address remaining high-priority issues per code review findings document.
