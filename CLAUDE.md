# Victor - macOS Hugo CMS

## Project Overview

**Victor** is a native macOS application built with SwiftUI that serves as a comprehensive Content Management System (CMS) for Hugo static sites. It provides a sophisticated editing experience with full site visibility, markdown editing, live preview, Hugo-specific features like frontmatter parsing, config GUI editing, and asset management.

### Vision
Create a native macOS app that feels better than editing Hugo sites in VS Code or other general-purpose editors by providing:
- Full Hugo site visibility with file-type-aware viewing/editing
- Hugo-aware file navigation with page bundle support
- Markdown editing with live preview
- Structured frontmatter editing (YAML/TOML/JSON)
- GUI-based Hugo configuration editor
- Asset browser with drag-drop insertion
- Auto-save with conflict detection
- Performance optimized for large Hugo sites (500+ files)

### Technical Stack
- **Platform**: macOS 14.0+ (Sonoma)
- **Framework**: SwiftUI with AppKit integration (NSTextView, WKWebView)
- **Architecture**: MVVM with `@Observable`
- **Build System**: XcodeGen + Swift Package Manager (project.yml → .xcodeproj)
- **Dependencies**: Down (Markdown), Yams (YAML), TOMLKit (TOML)

---

## Current Status: Production Ready + Active Development

**Last Updated**: 2026-01-05
**Build Status**: Clean build, no errors, no warnings
**Codebase Size**: 60 Swift files, ~14,590 lines of code

### Completed Phases

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1: File Type Infrastructure | COMPLETE | 19 file types, Hugo role detection |
| Phase 2: Multi-File Viewing | COMPLETE | Image viewer, text viewer, file router |
| Phase 3: Text File Editing | COMPLETE | Edit YAML, TOML, JSON, HTML, CSS, JS, etc. |
| Phase 4: Hugo Config GUI Editor | COMPLETE | Form/Raw views for hugo.toml/yaml/json |
| Phase 5: Data & Archetypes | NOT STARTED | Manage data/ files and archetypes |
| Phase 6: Asset Management | COMPLETE | Asset browser, drag-drop, detail panel |
| Phase 7: Template Editing | NOT STARTED | layouts/ and themes/ editing |
| Phase 8: Hugo Server Integration | NOT STARTED | Live preview via hugo server |

### Recent Updates (2026-01-05)

**Config Editor Improvements:**
- Fixed two-way sync between Form and Raw editor views
- Fixed YAML serialization issues (line wrapping, type normalization)
- Fixed boolean `false` values being dropped during round-trip
- Added `HugoConfigParserTests.swift` with comprehensive round-trip tests

**Asset Browser Fixes:**
- Fixed folder-specific asset display (was showing all assets)
- Proper folderURL parameter passing to AssetBrowserView

**UI Fixes:**
- Fixed folder click selection not registering
- Removed duplicate sidebar toggle buttons
- Added View menu sidebar toggle (Ctrl+Cmd+S)
- Conditional inspector button visibility for content files

### Previous Updates (2025-12-28 - 2026-01-01)

- Full-site Hugo CMS transformation (Phases 1-4, 6)
- Asset browser with grid/list views and drag-drop insertion
- Hugo config GUI editor with 4 tabs + raw YAML/TOML/JSON editing
- Image viewer with zoom/pan controls
- Text file editing for all code file types
- Tab-based editor layout with Cmd+1/2/3 shortcuts
- Word/character count status bar
- Breadcrumb navigation bar
- Inspector panel for metadata viewing

---

## Core Features

### Site Management
- Open and browse full Hugo sites with security-scoped bookmarks
- Hierarchical file tree navigation with expand/collapse
- 19 file types with type-specific icons and colors
- Hugo role detection (content, layouts, static, assets, data, etc.)
- Recursive file search across all folders
- Auto-restore last opened site on launch
- Hugo page bundle detection and visualization

### File Viewing & Editing
| File Type | Capability |
|-----------|------------|
| Markdown (.md) | Full editor + live preview + frontmatter |
| Images (.png, .jpg, .gif, .svg, .webp) | Viewer with zoom/pan |
| Config (hugo.toml/yaml/json) | GUI form editor + raw text |
| Code files (HTML, CSS, JS, TS, Go, etc.) | Syntax-aware text editor |
| Data files (YAML, TOML, JSON) | Text editor |
| Other | Open in default app |

### Hugo Config Editor
- **Form View**: Structured editing with 4 tabs (Essentials, Content, Taxonomies, Advanced)
- **Raw View**: Direct text editing with format preservation
- Supports YAML, TOML, and JSON config formats
- Two-way sync between Form and Raw views
- Custom fields preserved on save
- Round-trip format preservation (no data loss)

### Asset Browser
- Grid and list view modes with thumbnails
- Asset detail panel with metadata and preview
- Drag-drop insertion into markdown editor
- Copy shortcode/path to clipboard
- Folder-specific browsing (static/ or assets/)

### Markdown Editing
- High-performance NSTextView-based editor
- Formatting toolbar (bold, italic, headings, lists, code blocks)
- Live HTML preview with GitHub-flavored markdown styling
- Debounced preview updates (300ms) for smooth typing
- Current line highlighting
- Word/character count with cursor position

### Frontmatter Editing
- Parse and edit YAML, TOML, and JSON frontmatter
- **Form view**: Structured fields (title, date, draft, tags, categories, description)
- **Raw view**: Direct text editing with syntax awareness
- 5 organized tabs: Essential, Publishing, SEO, Menus, Advanced
- Chip-based tag/category input with flow layout
- Custom fields preserved on save

### File Operations
- Manual save (Cmd+S) and auto-save (2s debounce)
- Conflict detection when file modified externally
- User resolution options (Keep Editing / Reload from Disk)
- Undo/redo support
- Unsaved changes indicator

### Keyboard Shortcuts
| Shortcut | Action |
|----------|--------|
| Cmd+O | Open Hugo site folder |
| Cmd+S | Save current file |
| Cmd+F | Focus search field |
| Esc | Clear search field |
| Cmd+B | Bold formatting |
| Cmd+I | Italic formatting |
| Cmd+K | Insert link |
| Cmd+Shift+I | Insert image |
| Cmd+' | Block quote |
| Cmd+1/2/3 | Editor/Preview/Split mode |
| Ctrl+Cmd+S | Toggle sidebar |

---

## Architecture

### Design Pattern: MVVM with @Observable

```
User Action
    ↓
View (SwiftUI)
    ↓
ViewModel (@Observable @MainActor)
    ↓
Service (async/await or actor)
    ↓
Model
    ↓
View Update (automatic via @Observable)
```

### Key Architectural Decisions

1. **State Management: @Observable** - Modern Swift pattern, granular observation
2. **File Access: Security-Scoped Bookmarks** - App Sandbox ready
3. **Editor: NSTextView Wrapper** - Better performance than SwiftUI TextEditor
4. **Auto-Save: Actor-Based Service** - Thread-safe with conflict detection
5. **Layout: NavigationSplitView** - Native macOS three-column pattern
6. **File Router: Type-Based Dispatch** - FileViewerRouter selects appropriate viewer

---

## Code Structure

### Models (12 files)
| File | Purpose |
|------|---------|
| HugoSite.swift | Site representation with config detection |
| HugoSiteStructure.swift | Hugo directory role detection |
| HugoConfig.swift | Hugo config with form/raw sync |
| ContentFile.swift | Markdown file with frontmatter + content |
| TextFile.swift | Non-markdown text file |
| Asset.swift | Static/asset file representation |
| FileNode.swift | Tree structure for navigation |
| FileType.swift | 19 file type enum with icons/colors |
| Frontmatter.swift | Structured frontmatter |
| FrontmatterTypes.swift | Frontmatter type definitions |
| HugoShortcode.swift | Shortcode definition |

### ViewModels (3 files)
| File | Purpose |
|------|---------|
| SiteViewModel.swift | Global app state, file selection, search |
| EditorViewModel.swift | Markdown editor business logic |
| TextEditorViewModel.swift | Text file editor business logic |

### Services (7 files)
| File | Purpose |
|------|---------|
| FileSystemService.swift | File I/O, bookmarks, directory scanning |
| AutoSaveService.swift | Debounced saves with conflict detection (actor) |
| FrontmatterParser.swift | YAML/TOML/JSON frontmatter parsing |
| HugoConfigParser.swift | Hugo config parsing and serialization |
| AssetService.swift | Asset discovery and metadata |
| MarkdownRenderer.swift | Markdown to HTML conversion |
| Logger.swift | Logging utilities |

### Views (~38 files)
```
MainWindow/
  ├── ContentView.swift          # Three-column NavigationSplitView
  ├── EditorPanelView.swift      # Markdown editor panel
  ├── FrontmatterBottomPanel.swift
  ├── PreviewPanel.swift
  ├── SidebarView.swift
  ├── FileListView.swift
  ├── TabBarView.swift
  └── BreadcrumbBar.swift

Editor/
  ├── EditorTextView.swift       # NSTextView wrapper
  ├── EditorStatusBar.swift      # Word/char count
  ├── FrontmatterEditorView.swift
  ├── TextEditorPanel.swift      # Non-markdown editor
  ├── ShortcodePickerView.swift
  ├── Components/                # Reusable editor components
  └── Tabs/                      # Frontmatter tab views

ConfigEditor/
  └── ConfigEditorView.swift     # Hugo config GUI editor

AssetBrowser/
  ├── AssetBrowserView.swift     # Grid/list asset browser
  └── AssetDetailPanel.swift     # Asset metadata panel

Viewers/
  ├── FileViewerRouter.swift     # Routes to appropriate viewer
  ├── ImageViewerPanel.swift     # Image viewer with zoom
  ├── TextViewerPanel.swift      # Read-only text viewer
  └── UnsupportedFilePanel.swift

Inspector/
  ├── InspectorPanel.swift
  ├── MetadataSection.swift
  └── StatisticsSection.swift

FocusMode/
  └── FocusModeView.swift

Preview/
  └── PreviewWebView.swift       # WKWebView wrapper

Preferences/
  └── PreferencesView.swift
```

### Tests (2 files)
| File | Purpose |
|------|---------|
| FrontmatterParserTests.swift | Frontmatter round-trip tests |
| HugoConfigParserTests.swift | Config parsing and serialization tests |

---

## Development Guide

### XcodeGen Workflow

This project uses **XcodeGen** to generate the Xcode project from `project.yml`.

**Adding new files:**
1. Create new Swift file(s) in the appropriate directory
2. Regenerate: `xcodegen generate`
3. Build to verify: `xcodebuild -project Victor.xcodeproj -scheme Victor build`

### Build & Run

```bash
xcodegen generate          # Regenerate project if needed
open Victor.xcodeproj      # Open in Xcode, then Cmd+R
```

**Command Line Build:**
```bash
xcodebuild -project Victor.xcodeproj -scheme Victor -configuration Debug build
```

**Run Tests:**
```bash
xcodebuild test -project Victor.xcodeproj -scheme Victor -destination 'platform=macOS'
```

### Code Style & Conventions

- Follow Swift API Design Guidelines
- All ViewModels: `@MainActor @Observable`
- All file operations: `async/await`
- Heavy background work: `actor` (AutoSaveService)
- Extract views when > 50 lines
- Use `@Bindable` for binding to `@Observable` objects
- Use `// MARK: -` to organize code sections

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| Down | 0.11.0 | Markdown to HTML conversion |
| Yams | 5.x | YAML parsing (frontmatter, config) |
| TOMLKit | 0.6.0 | TOML parsing (frontmatter, config) |

### Yams Usage Notes
- Returns `Dictionary<AnyHashable, Any>` - must normalize to `[String: Any]`
- Use `width: -1` to prevent line wrapping in serialization
- Always validate round-trip with parse after serialize

---

## Planned Features (Not Yet Implemented)

### Phase 5: Data & Archetypes Management
- GUI for editing data/ files (JSON, YAML, TOML)
- Archetype template management
- Create new content from archetypes

### Phase 7: Template Editing
- layouts/ directory editing
- Theme file browsing
- Template syntax highlighting

### Phase 8: Hugo Server Integration
- Built-in hugo server controls
- True live preview
- Build status indicators

### UI Stage 3: Navigation Improvements
- UI-012: File status indicators in sidebar

### Other Planned Features
- File system watching (FSEvents) for auto-reload
- Git integration (status, commit, push)
- Syntax highlighting for code blocks
- Search & replace across files
- VoiceOver improvements
- Custom themes/color schemes

---

## Key Implementation Notes

### Hugo Config Form/Raw Sync
```swift
// Form → Raw (on switching to raw view):
let serialized = try HugoConfigParser.shared.serialize(config)
config.rawContent = serialized

// Raw → Form (on switching to form view):
try config.updateFromRawContent()
```

### Type Normalization for Yams
```swift
// Yams returns Dictionary<AnyHashable, Any> which can't be serialized back
// Must normalize recursively:
private func normalizeForSerialization(_ value: Any) -> Any {
    if let dict = value as? [AnyHashable: Any] {
        var normalized: [String: Any] = [:]
        for (key, val) in dict {
            if let stringKey = key as? String {
                normalized[stringKey] = normalizeForSerialization(val)
            }
        }
        return normalized
    }
    // ... handle arrays and other types
}
```

### Boolean Serialization
Always include boolean fields regardless of value (don't skip `false`):
```swift
dictionary["buildDrafts"] = config.buildDrafts  // Always include
dictionary["buildFuture"] = config.buildFuture
dictionary["buildExpired"] = config.buildExpired
```

---

## Debugging Tips

### Config Editor Issues
1. Check console for `[HugoConfigParser]` and `[HugoConfig]` logs
2. Verify round-trip with tests: `testExplicitFalseValuesPreserved`
3. Check type normalization for nested dictionaries

### File Types Not Detected
1. Check `FileType.swift` extension mapping
2. Verify `HugoSiteStructure.swift` role detection
3. Check `FileViewerRouter.swift` routing logic

### Assets Not Loading
1. Verify folder is in static/ or assets/ directory
2. Check `AssetService.swift` scan logic
3. Verify folder permissions (sandbox)

---

## Resources

### Apple Documentation
- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [NSTextView](https://developer.apple.com/documentation/appkit/nstextview)
- [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)
- [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox)

### Hugo Documentation
- [Content Organization](https://gohugo.io/content-management/organization/)
- [Frontmatter](https://gohugo.io/content-management/front-matter/)
- [Page Bundles](https://gohugo.io/content-management/page-bundles/)
- [Configuration](https://gohugo.io/getting-started/configuration/)

### Project Documentation
- `FULL-SITE-CMS-PLAN.md` - Detailed implementation plan with code snippets
- `Docs/FRONTMATTER-ENHANCEMENT-PLAN.md` - Frontmatter editor improvements
- `Docs/SHORTCODE-IMPLEMENTATION-PLAN.md` - Shortcode picker design
- `Docs/CODE-REVIEW-ISSUES.yaml` - Code review findings

---

## For Future Claude Sessions

1. **Current State**: Full-site CMS with config editor, asset browser, multi-file support
2. **Architecture**: MVVM with @Observable, security-scoped bookmarks, actor-based auto-save
3. **Code Location**: `/Users/karan/Developer/macos/victor/`
4. **Build Method**: XcodeGen → Victor.xcodeproj
5. **Key Files**: FileViewerRouter.swift, HugoConfigParser.swift, AssetBrowserView.swift

### Quick Context
- 60 Swift files, ~14,590 LOC
- Build: Clean, no errors, no warnings
- Phases 1-4 and 6 complete, Phases 5/7/8 not started
- Recent work: Config editor Form/Raw sync fixes, boolean serialization

---

**Document Version**: 5.0 (Full-Site CMS Update)
**Last Updated**: 2026-01-05
**Status**: Production Ready - Active Development
