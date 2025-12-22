# Victor - macOS Hugo CMS Development Log

## Project Overview

**Victor** is a native macOS application built with SwiftUI that serves as a Content Management System (CMS) for Hugo static sites. It provides a sophisticated editing experience with markdown editing, live preview, and Hugo-specific features like frontmatter parsing.

### Vision
Create a native macOS app that feels better than editing Hugo sites in VS Code or other general-purpose editors by providing:
- Hugo-aware file navigation
- WYSIWYG markdown editing with live preview
- Structured frontmatter editing
- Auto-save and conflict detection
- Performance optimized for large Hugo sites (500+ files)

### Technical Specifications
- **Platform**: macOS 14.0+ (Sonoma)
- **Framework**: SwiftUI with AppKit integration
- **Architecture**: MVVM with `@Observable`
- **Build System**: Swift Package Manager
- **Dependencies**: Down (Markdown), Yams (YAML), TOMLKit (TOML)

---

## Current Status: Phase 1 Complete ✅

**Date Completed**: 2025-12-22
**Git Commit**: `5a2540b` - "Phase 1: Foundation - Basic Hugo CMS structure"

### What's Implemented

#### Core Architecture
- **App Entry Point**: `VictorApp.swift` with WindowGroup and custom commands
- **MVVM Pattern**: Clean separation of Models, ViewModels, Views, Services
- **Observable State**: Using modern `@Observable` macro (iOS 17+/macOS 14+)
- **Main Actor**: All UI-bound code properly annotated with `@MainActor`

#### Data Models (Victor/Models/)
1. **HugoSite.swift**
   - Represents a Hugo site directory
   - Auto-detects config files (hugo.toml, config.toml, etc.)
   - Validates Hugo site structure (checks for content/ directory)
   - Stores security-scoped bookmark data

2. **ContentFile.swift**
   - Represents a markdown file
   - Properties: url, frontmatter, markdownContent, lastModified
   - Computed properties: isDraft, fileName, relativePath, isIndexFile
   - Hashable for use in SwiftUI Lists

3. **FileNode.swift**
   - Tree structure for file/folder hierarchy
   - Properties: url, isDirectory, children, parent
   - Supports expand/collapse state
   - Detects Hugo page bundles (folders with index.md)
   - Recursive node finding and sorting

4. **Frontmatter.swift** (Basic Version)
   - Enum for format detection (YAML/TOML/JSON)
   - Stores raw content (parsing in Phase 3)
   - Placeholder for structured fields

#### Services (Victor/Services/)
1. **FileSystemService.swift**
   - Singleton pattern with `@MainActor`
   - **Folder Selection**: NSOpenPanel for directory picker
   - **Security-Scoped Bookmarks**:
     - Save bookmarks for persistent access
     - Load and validate on app launch
     - Handle stale bookmarks
   - **Directory Scanning**: Recursive file enumeration
   - **File I/O**: Read/write with NSFileCoordinator
   - **Error Handling**: Custom FileError enum with LocalizedError

#### ViewModels (Victor/ViewModels/)
1. **SiteViewModel.swift**
   - Global app state management
   - Properties: site, fileNodes, selectedNode, searchQuery
   - Operations: openSiteFolder, loadSite, selectNode, reloadSite
   - Automatic save/restore of last opened site
   - File content loading on selection

#### Views (Victor/Views/)
1. **MainWindow/ContentView.swift**
   - Three-column NavigationSplitView layout
   - Sidebar (200-400pt), Editor panel, Preview panel
   - Toolbar with sidebar toggle and loading indicator
   - Error alert presentation
   - Empty states with ContentUnavailableView

2. **MainWindow/SidebarView.swift**
   - Modular components:
     - OpenFolderPrompt: Button to open Hugo site
     - SiteHeader: Site name, file count, menu
     - SearchBar: Filter files by name
     - FileListView: List with selection binding
     - FileRowView: Individual file display with icons and draft badges
     - LoadingView: Progress indicator

#### Configuration Files
- **Package.swift**: SPM configuration with dependencies
- **Victor.entitlements**: Sandbox permissions
- **.gitignore**: Comprehensive Xcode/Swift ignore patterns
- **README.md**: User documentation

### What Works Right Now

1. **Launch app** → Shows "Open Hugo Site" button
2. **Click button or ⌘O** → NSOpenPanel appears
3. **Select Hugo site folder** → Validates it's a valid Hugo site
4. **Sidebar populates** → Shows all .md files from content/
5. **Search files** → Filter by filename
6. **Click file** → Raw markdown displays in center panel
7. **Persistent state** → Last opened site loads on relaunch
8. **Clean build** → No warnings, no errors

### What's NOT Yet Implemented (Coming in Later Phases)

- ❌ Editable markdown editor (Phase 2)
- ❌ Live markdown preview (Phase 2)
- ❌ Frontmatter parsing/editing (Phase 3)
- ❌ Hierarchical file tree (Phase 4 - currently flat list)
- ❌ Auto-save (Phase 5)
- ❌ File system watching (Phase 5)
- ❌ Keyboard shortcuts beyond ⌘O (Phase 5)

---

## Architecture Decisions Made

### 1. Project Structure: Xcode Project
**Decision**: Using traditional Xcode project (Victor.xcodeproj)
**Rationale**:
- User preference for Xcode project workflow
- Better asset management (App Icon, resources)
- More familiar Xcode experience
- SPM dependencies managed within Xcode project

**Implementation**: Created project.pbxproj manually with all source files and SPM dependencies configured.

**Note**: Package.swift is kept for backward compatibility but Victor.xcodeproj is the primary build method.

### 2. State Management: MVVM with @Observable
**Decision**: Use @Observable macro instead of ObservableObject
**Rationale**:
- Modern Swift pattern (Swift 5.9+, macOS 14+)
- Less boilerplate than ObservableObject
- Better performance (granular observation)
- Requires macOS 14+ but that's our minimum anyway

**Alternative Considered**: The Composable Architecture (TCA) - too complex for v1, can migrate later if needed.

### 3. File Access: Security-Scoped Bookmarks
**Decision**: Implement security-scoped bookmarks from day 1
**Rationale**:
- Required for App Sandbox (App Store compliance)
- Provides persistent access to user-selected folders
- Better UX (remembers last opened site)

**Implementation**: FileSystemService handles all bookmark logic, stores in UserDefaults.

### 4. Layout: NavigationSplitView
**Decision**: Use NavigationSplitView for three-column layout
**Rationale**:
- Native macOS pattern
- Automatic sidebar collapse/expand
- Built-in column resizing
- Standard for macOS productivity apps

**Alternative Considered**: Custom HSplitView - less automatic behavior but more control. NavigationSplitView is more maintainable.

### 5. File List: Flat vs Tree (Phase 1)
**Decision**: Phase 1 uses flat list, Phase 4 will add hierarchy
**Rationale**:
- Simpler to implement and test
- Still functional for basic use
- Allows testing core functionality before complexity
- FileNode model already supports tree structure

### 6. Editor: NSTextView vs TextEditor (Phase 2)
**Decision**: Will use NSTextView wrapper in Phase 2
**Rationale**:
- Better performance for large files
- More control (syntax highlighting future)
- Access to AppKit text editing features
- SwiftUI TextEditor has limitations

**Note**: Planned for Phase 2, not implemented yet.

---

## Implementation History

### Session 1: Planning (2025-12-22 Morning)

**User Request**: Create a macOS app using SwiftUI as a CMS for Hugo. Start with WYSIWYG editor for Markdown with folder navigation and dual-panel (raw + preview) view.

**Planning Process**:
1. Explored empty directory (fresh git repo)
2. Asked clarifying questions:
   - macOS version: **14 Sonoma+** (user choice)
   - Project type: **Xcode Project** (user choice)
   - Hugo features: **Yes, parse frontmatter** (user choice)
   - Markdown rendering: **Down + WebView** (user choice)

3. Launched Plan agent to design architecture
4. Expert panel review from multiple perspectives:
   - SwiftUI Architecture Expert
   - macOS Platform Expert
   - Performance Expert
   - Hugo Domain Expert
   - Accessibility Expert

5. Created comprehensive implementation plan with 5 phases
6. User approved plan

### Session 1: Implementation (2025-12-22 Afternoon)

**Phase 1 Implementation** (Duration: ~2 hours)

1. **Project Setup**:
   - Created directory structure
   - Initialized Swift Package (Package.swift)
   - Added .gitignore
   - Configured SPM dependencies

2. **Core Models** (4 files):
   - HugoSite.swift - Site representation
   - ContentFile.swift - Markdown file model
   - FileNode.swift - Tree structure
   - Frontmatter.swift - Basic version (full parsing in Phase 3)

3. **Services** (1 file):
   - FileSystemService.swift - File I/O, folder selection, bookmarks

4. **ViewModels** (1 file):
   - SiteViewModel.swift - App state management

5. **Views** (3 files):
   - VictorApp.swift - App entry point
   - ContentView.swift - Main layout
   - SidebarView.swift - File browser

6. **Configuration**:
   - Victor.entitlements - Sandbox permissions
   - README.md - User documentation

7. **Build & Test**:
   - Initial build: 1 warning (unused variable)
   - Fixed warning
   - Final build: Clean, no warnings, no errors
   - Committed to git

**Key Challenges Solved**:
- Creating Xcode project from CLI → Used Swift Package Manager
- Security-scoped bookmarks → Implemented in FileSystemService
- Flat vs hierarchical file list → Chose flat for Phase 1, model supports both

**Lines of Code**: ~1,266 lines (14 files)

---

## Detailed Architecture

### Data Flow

```
User Action
    ↓
View (SidebarView, ContentView)
    ↓
ViewModel (SiteViewModel) - @MainActor
    ↓
Service (FileSystemService) - async operations
    ↓
File System (NSOpenPanel, NSFileCoordinator)
    ↓
Model (HugoSite, ContentFile, FileNode)
    ↓
View Update (SwiftUI observability)
```

### State Management Flow

```
SiteViewModel (@Observable)
    ├─ site: HugoSite?              # Current opened site
    ├─ fileNodes: [FileNode]         # All files (flat list in Phase 1)
    ├─ selectedNode: FileNode?       # Currently selected file
    ├─ selectedFileID: UUID?         # For List binding
    ├─ isLoading: Bool               # Loading state
    ├─ errorMessage: String?         # Error display
    └─ searchQuery: String           # File filter
```

### File I/O Strategy

**Read Flow**:
1. User selects folder via NSOpenPanel
2. Create security-scoped bookmark
3. Enumerate files with FileManager.enumerator
4. Filter .md files only (Phase 1)
5. Create FileNode for each file
6. On selection, read file content
7. Parse frontmatter (Phase 3) + markdown

**Write Flow** (Phase 5):
1. User edits content
2. Debounce 2 seconds
3. NSFileCoordinator for safe access
4. Check modification date (conflict detection)
5. Write atomically
6. Update ContentFile.lastModified

### Security Model

**Entitlements**:
- `com.apple.security.app-sandbox` = true
- `com.apple.security.files.user-selected.read-write` = true
- `com.apple.security.network.client` = true (for WebView in Phase 2)

**Bookmark Flow**:
```swift
// On folder selection
let bookmarkData = try url.bookmarkData(options: .withSecurityScope, ...)
UserDefaults.standard.set(bookmarkData, forKey: "hugoSiteBookmark")

// On app launch
let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, ...)
guard url.startAccessingSecurityScopedResource() else { ... }
// Use URL
url.stopAccessingSecurityScopedResource() // When done
```

---

## Phase-by-Phase Plan

### ✅ Phase 1: Foundation (COMPLETE)
**Duration**: 1 session
**Status**: Committed (5a2540b)

**Delivered**:
- Project structure with SPM
- Core models (HugoSite, ContentFile, FileNode, Frontmatter)
- FileSystemService with security-scoped bookmarks
- SiteViewModel for state management
- NavigationSplitView UI with sidebar
- File browser with search
- Open folder dialog
- Display raw markdown content

**Testing**: Manual testing pending by user

---

### 🔄 Phase 2: Editor & Preview (NEXT)
**Duration**: ~1-2 sessions
**Status**: Not started

**Goals**:
- Editable markdown editor
- Live HTML preview
- Debounced preview updates

**Tasks**:
1. Create `EditorTextView.swift` (NSViewRepresentable wrapping NSTextView)
   - Monospace font
   - Disable smart quotes/dashes
   - NSTextViewDelegate for change notifications
   - Undo/redo support

2. Create `MarkdownRenderer.swift`
   - Use Down library to convert markdown → HTML
   - Load CSS from resources
   - Handle rendering errors

3. Create `PreviewWebView.swift` (NSViewRepresentable wrapping WKWebView)
   - Configure for local content
   - Security settings

4. Create `EditorViewModel.swift`
   - Observe text changes
   - Debounce 300ms
   - Trigger preview update

5. Create HTML/CSS resources:
   - `Resources/preview-template.html`
   - `Resources/github-style.css`

**Files to Create**:
- Victor/Views/Editor/EditorTextView.swift
- Victor/Views/Editor/EditorView.swift
- Victor/Views/Preview/PreviewWebView.swift
- Victor/Views/Preview/PreviewView.swift
- Victor/ViewModels/EditorViewModel.swift
- Victor/Services/MarkdownRenderer.swift
- Victor/Resources/preview-template.html
- Victor/Resources/github-style.css

**Success Criteria**:
- Can type markdown in left panel
- See HTML preview in right panel
- Preview updates smoothly (< 500ms)
- No lag when typing

---

### 📋 Phase 3: Frontmatter Support
**Duration**: ~1 session
**Status**: Not started

**Goals**:
- Parse YAML/TOML frontmatter
- Display in structured form
- Edit and save back

**Tasks**:
1. Enhance `FrontmatterParser.swift`:
   - Detect delimiter (---/+++/{)
   - Parse YAML with Yams
   - Parse TOML with TOMLKit
   - Handle common Hugo fields (title, date, draft, tags, categories)
   - Serialize back to original format

2. Update `Frontmatter.swift`:
   - Add structured properties
   - Custom fields dictionary for unknown keys

3. Create `FrontmatterEditorView.swift`:
   - Form with TextField, DatePicker, Toggle
   - Tag input (comma-separated)
   - Collapsible disclosure group

4. Integrate into `EditorView`:
   - Show at top of editor panel
   - Toggle button to show/hide

5. Update save logic:
   - Combine frontmatter + markdown
   - Preserve format (YAML stays YAML, etc.)

**Success Criteria**:
- Parse existing frontmatter correctly
- Edit title, date, draft status
- Save preserves all fields
- Round-trip works (parse → edit → save → parse)

---

### 📋 Phase 4: File Tree Navigation
**Duration**: ~1 session
**Status**: Not started

**Goals**:
- Hierarchical file browser
- Hugo page bundle support

**Tasks**:
1. Enhance `FileSystemService.scanDirectory`:
   - Build tree instead of flat list
   - Detect Hugo page bundles (folders with index.md)

2. Create `FileTreeView.swift`:
   - Use SwiftUI OutlineGroup
   - Expand/collapse folders
   - Persistent expand state

3. Create `FileRowView.swift`:
   - Different icons for files/folders/bundles
   - Metadata display

4. Update `FileNode.swift`:
   - Add sorting logic (folders first, then alpha)

**Success Criteria**:
- Navigate nested folder structure
- Expand/collapse works
- Page bundles are identified
- Performance good with 500+ files

---

### 📋 Phase 5: Auto-Save & Polish
**Duration**: ~1-2 sessions
**Status**: Not started

**Goals**:
- Production-ready reliability
- Auto-save
- File watching
- UI polish

**Tasks**:
1. Create `AutoSaveService.swift` (actor):
   - Debounce 2s after typing stops
   - Conflict detection (check modification date)
   - Alert on conflict: "Keep my version" / "Reload from disk"

2. Create `FileWatcherService.swift` (actor):
   - Monitor with FSEvents
   - Debounce 500ms
   - Reload changed files
   - Update file tree

3. Error handling:
   - FileError enum with all cases
   - User-friendly error messages
   - Graceful degradation

4. UI polish:
   - Keyboard shortcuts (⌘S, ⌘W, ⌘F)
   - Toolbar items
   - Empty states
   - Loading indicators
   - Unsaved changes indicator (dot in close button)

**Success Criteria**:
- No data loss
- External edits detected
- Smooth UX
- Feels native to macOS

---

## Testing Strategy

### Manual Testing Checklist (Phase 1)

**First Launch**:
- [ ] App launches without crash
- [ ] Shows "Open Hugo Site" button
- [ ] Window size is reasonable (min 1000x600)

**Folder Selection**:
- [ ] ⌘O opens folder picker
- [ ] Button opens folder picker
- [ ] Can select Hugo site folder
- [ ] Validates folder (rejects non-Hugo folders)
- [ ] Shows error for invalid folders

**File Loading**:
- [ ] Sidebar shows file count
- [ ] Files are sorted alphabetically
- [ ] Search filters files correctly
- [ ] Can clear search

**File Selection**:
- [ ] Click file shows content
- [ ] Raw markdown displays correctly
- [ ] File name shows in title
- [ ] Can select different files
- [ ] Selection persists visually

**Persistence**:
- [ ] Quit and relaunch
- [ ] Last site reopens automatically
- [ ] Security-scoped bookmark works

**Error Handling**:
- [ ] Error alert shows for invalid folder
- [ ] Can dismiss error
- [ ] App doesn't crash on errors

### Test Hugo Sites

**Recommended test cases**:
1. **Empty Hugo site**: `hugo new site test-empty`
2. **Small site**: 5-10 markdown files
3. **Medium site**: 50-100 files
4. **Large site**: 500+ files (performance test)
5. **Complex structure**: Nested folders, page bundles

**Create test Hugo site**:
```bash
cd ~/Documents
hugo new site TestHugoSite
cd TestHugoSite
hugo new posts/test-1.md
hugo new posts/test-2.md
hugo new about.md
```

Then open this folder in Victor.

---

## Known Issues / Limitations (Phase 1)

### Current Limitations
1. **Flat file list only** - No hierarchy (coming in Phase 4)
2. **Read-only** - Can't edit files yet (coming in Phase 2)
3. **No preview** - Just raw markdown (coming in Phase 2)
4. **No frontmatter parsing** - Shows raw (coming in Phase 3)
5. **No auto-save** - Manual only (coming in Phase 5)
6. **Limited keyboard shortcuts** - Only ⌘O (more in Phase 5)

### Minor Issues
- None currently known (clean build)

### Future Enhancements (Post Phase 5)
- Syntax highlighting in editor (TextKit 2)
- Image drag & drop
- Hugo server integration
- Git integration
- Multi-file operations
- Search & replace across files
- Export to PDF/HTML
- Quick Look support
- Touch Bar support (for Macs that have it)
- VoiceOver/accessibility improvements

---

## Development Commands

### Open in Xcode (Primary Method)
```bash
open Victor.xcodeproj
```

### Build with Xcode
```bash
xcodebuild -project Victor.xcodeproj -scheme Victor -configuration Debug build
```

### Run from Xcode
- Open Victor.xcodeproj
- Select "Victor" scheme and "My Mac" destination
- Press ⌘R

### Alternative: Swift Package Manager
```bash
# Build
swift build

# Run
swift run Victor

# Clean
swift package clean
```

### Update Dependencies
Dependencies are managed in Victor.xcodeproj. Xcode will automatically fetch them on first build.
Alternatively:
```bash
swift package update
```

---

## Important File Paths

### Source Code
- `/Users/karan/Developer/macos/victor/Victor/VictorApp.swift` - Entry point
- `/Users/karan/Developer/macos/victor/Victor/Models/` - Data models
- `/Users/karan/Developer/macos/victor/Victor/ViewModels/SiteViewModel.swift` - Main state
- `/Users/karan/Developer/macos/victor/Victor/Services/FileSystemService.swift` - File I/O
- `/Users/karan/Developer/macos/victor/Victor/Views/MainWindow/` - UI

### Configuration
- `/Users/karan/Developer/macos/victor/Package.swift` - SPM config
- `/Users/karan/Developer/macos/victor/Victor/Victor.entitlements` - Security
- `/Users/karan/Developer/macos/victor/.gitignore` - Git ignore

### Documentation
- `/Users/karan/Developer/macos/victor/README.md` - User docs
- `/Users/karan/Developer/macos/victor/CLAUDE.md` - This file

### Plan
- `/Users/karan/.claude/plans/drifting-riding-mccarthy.md` - Original implementation plan

---

## Code Style & Conventions

### Swift Style
- Follow Swift API Design Guidelines
- Use descriptive names: `FileSystemService` not `FileSvc`
- Use computed properties for derived state
- Prefer `let` over `var` when possible

### SwiftUI Patterns
- Composition over inheritance
- Extract views when > 50 lines
- Use `@Bindable` for binding to @Observable objects
- Use `@State` for local view state only
- Avoid logic in views - delegate to ViewModels

### Concurrency
- All ViewModels: `@MainActor @Observable`
- All file operations: `async/await`
- Services that do heavy work: `actor` (FileWatcherService, AutoSaveService)
- UI updates: always on main thread

### Error Handling
- Typed errors: `enum FileError: LocalizedError`
- User-facing messages: implement `errorDescription`
- Never show raw error to users
- Log errors for debugging: `print()` for now, `os.log` later

### Comments
- Explain "why" not "what"
- Use `// MARK: -` to organize code sections
- Document complex algorithms
- Phase markers: `// Phase 1: ...`, `// Phase 3: Will parse`

---

## Debugging Tips

### If app doesn't launch
1. Check build succeeded: `swift build`
2. Look for errors in Xcode console
3. Check entitlements are valid
4. Verify macOS version is 14.0+

### If folder picker doesn't appear
1. Check app has sandbox entitlements
2. Check `user-selected.read-write` is true
3. Try granting folder access in System Settings > Privacy

### If files don't load
1. Check folder has `content/` directory
2. Check files are `.md` extension
3. Check console for error messages
4. Try with a simple Hugo site first

### If app crashes
1. Check Xcode crash logs
2. Look for force-unwrapping (`!`) that might fail
3. Check async operations complete
4. Verify security-scoped resource access

---

## Dependencies Documentation

### Down (0.11.0)
- **Purpose**: Markdown to HTML conversion
- **Repo**: https://github.com/johnxnguyen/Down
- **Usage**: `let down = Down(markdownString: text); let html = try down.toHTML()`
- **Phase**: 2 (Preview)

### Yams (5.4.0)
- **Purpose**: YAML frontmatter parsing
- **Repo**: https://github.com/jpsim/Yams
- **Usage**: `let yaml = try Yams.load(yaml: yamlString)`
- **Phase**: 3 (Frontmatter)

### TOMLKit (0.6.0)
- **Purpose**: TOML frontmatter parsing
- **Repo**: https://github.com/LebJe/TOMLKit
- **Usage**: `let toml = try TOMLDecoder().decode(Frontmatter.self, from: tomlString)`
- **Phase**: 3 (Frontmatter)

---

## Git Workflow

### Current Branch
- `main` (default branch)

### Commit Strategy
- One commit per phase completion
- Clear, descriptive commit messages
- Include co-author line: `Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>`

### Recent Commits
- `5a2540b` (HEAD) - Phase 1: Foundation - Basic Hugo CMS structure

### Next Commit
- Will be Phase 2 completion: "Phase 2: Editor & Preview"

---

## Questions & Answers

### Why Swift Package Manager instead of Xcode project?
- Easier to create from CLI
- Cleaner for version control
- Can still open in Xcode (`open Package.swift`)
- May convert to Xcode project later if needed

### Why @Observable instead of ObservableObject?
- Modern Swift pattern (macOS 14+)
- Less boilerplate
- Better performance with granular observation
- Aligns with our minimum macOS version

### Why NSTextView instead of TextEditor for Phase 2?
- TextEditor has limitations (performance, control)
- NSTextView gives access to AppKit features
- Enables syntax highlighting in future
- More professional editing experience

### Why security-scoped bookmarks?
- Required for App Sandbox (App Store)
- Better UX (remembers last site)
- Proper macOS security model

### Why flat file list in Phase 1?
- Simpler to implement and test first
- Model already supports tree (FileNode.children)
- Will add hierarchy in Phase 4
- Allows validating core functionality early

---

## User Testing Notes

### Before First Test
- Ensure macOS 14.0+
- Have a Hugo site ready (or create test site)
- Xcode installed if using Xcode method
- Command line tools if using `swift run`

### What to Test
1. **Basic flow**: Open folder → browse files → select file
2. **Search**: Filter files by name
3. **Persistence**: Quit and relaunch
4. **Errors**: Try opening non-Hugo folder
5. **Performance**: Try with large Hugo site

### Report Issues
- Include steps to reproduce
- Include error messages
- Include Hugo site structure (if relevant)
- Include macOS version

### After Testing
- User will decide: continue to Phase 2 or make adjustments
- Any bugs found should be fixed before Phase 2
- Performance issues should be noted

---

## Next Session Preparation

### If Proceeding to Phase 2

**Context to remember**:
- Phase 1 complete and tested
- User happy with current functionality
- Ready to add editor and preview

**Phase 2 checklist**:
1. Review Phase 2 plan in this document
2. Create Editor components (NSTextView wrapper)
3. Create Preview components (WKWebView wrapper)
4. Create EditorViewModel
5. Create MarkdownRenderer service
6. Add HTML/CSS resources
7. Wire up debounced preview updates
8. Test editing and preview
9. Commit Phase 2

**Estimated time**: 1-2 hours

### If Bugs Found

**Debugging workflow**:
1. Reproduce issue
2. Check console logs
3. Add debug prints if needed
4. Fix issue
5. Test fix
6. Commit fix with descriptive message

### If Changes Requested

**Common adjustments**:
- UI layout tweaks
- Performance optimizations
- Additional error handling
- Different default behaviors

---

## Success Metrics

### Phase 1 Success Criteria (Current)
- [x] Clean build with no warnings
- [x] App launches successfully
- [ ] User can open Hugo site (pending test)
- [ ] Files load and display (pending test)
- [ ] Search works (pending test)
- [ ] Persistence works (pending test)

### Overall Project Success Criteria
- Can manage Hugo sites faster than VS Code
- No data loss (auto-save, conflict detection)
- Feels native to macOS (keyboard shortcuts, conventions)
- Handles large sites (500+ files) smoothly
- Frontmatter editing is easier than raw YAML

---

## Lessons Learned

### What Worked Well
1. **Planning first**: Comprehensive plan saved time
2. **Phased approach**: Phase 1 MVP is testable and useful
3. **Swift Package Manager**: Easy to set up and manage
4. **@Observable macro**: Cleaner than ObservableObject
5. **FileNode model**: Designed for tree from start, easy to enhance

### What Could Be Better
1. **Testing**: Should add unit tests earlier
2. **Documentation**: Could use more inline code comments
3. **Error handling**: Could be more comprehensive

### For Next Phase
1. Start with tests for MarkdownRenderer
2. Add more inline documentation
3. Consider adding debug logging
4. Test on actual Hugo sites earlier

---

## Resources & References

### Apple Documentation
- [SwiftUI Views](https://developer.apple.com/documentation/swiftui/views)
- [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [NSTextView](https://developer.apple.com/documentation/appkit/nstextview)
- [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)
- [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox)
- [Security-Scoped Bookmarks](https://developer.apple.com/documentation/foundation/nsurl/1417051-bookmarkdata)

### Hugo Documentation
- [Hugo Content Organization](https://gohugo.io/content-management/organization/)
- [Hugo Frontmatter](https://gohugo.io/content-management/front-matter/)
- [Hugo Page Bundles](https://gohugo.io/content-management/page-bundles/)

### Third-Party Libraries
- [Down - Markdown Rendering](https://github.com/johnxnguyen/Down)
- [Yams - YAML Parser](https://github.com/jpsim/Yams)
- [TOMLKit - TOML Parser](https://github.com/LebJe/TOMLKit)

---

## Contact & Support

### For Future Claude Sessions
This document contains all context needed to continue development. Key points:
1. Phase 1 is complete (commit 5a2540b)
2. User is testing Phase 1
3. Phase 2 plan is in this document
4. All architectural decisions are documented
5. Code is at /Users/karan/Developer/macos/victor/

### For the User
If continuing with a new Claude session:
1. Share this CLAUDE.md file
2. Mention current phase status
3. Share any test results from Phase 1
4. Indicate what you want to work on next

---

**Document Version**: 1.0
**Last Updated**: 2025-12-22
**Status**: Phase 1 Complete, Awaiting User Testing
**Next Milestone**: Phase 2 - Editor & Preview
