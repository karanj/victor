# Victor - macOS Hugo CMS

A native macOS app built with SwiftUI that provides a sophisticated editing experience for Hugo static sites.

**Last Updated**: December 29, 2025
**Build Status**: Clean build, no errors, no warnings
**Code Quality**: All critical, high-priority, and medium-priority issues fixed
**Architecture**: MVVM with @Observable, security-scoped bookmarks, actor-based auto-save

## Features

### Site Content Management

- Open and browse Hugo site folders
- Hierarchical file tree navigation with expand/collapse
- File search (recursive through folders)
- Security-scoped bookmarks for persistent folder access
- Recent sites list for quick access
- File status indicators (modified, recently saved)

### Layout Modes

- **Editor Mode** (⌘1): Full-width markdown editor
- **Preview Mode** (⌘2): Full-width rendered preview
- **Split Mode** (⌘3): Side-by-side editor and preview
- Tab bar for easy mode switching
- Layout preference persisted across sessions

### Markdown Editing

- High-performance NSTextView-based editor
- Current line highlighting
- Word count, character count, and cursor position in status bar
- Formatting toolbar with grouped controls:
  - Text formatting (Bold, Italic)
  - Headings dropdown (H1-H6)
  - Lists (Bullet, Numbered)
  - Block elements (Code, Quote)
  - Insert elements (Link, Image)
- Monospace font with configurable size
- Live HTML preview with GitHub-style rendering
- Debounced preview updates (300ms) for smooth typing

### Focus Mode (⌃⌘F)

- Distraction-free writing environment
- Centered text with comfortable max-width
- Hidden sidebar, toolbar, and chrome
- Word count and scroll progress indicator
- Press Escape to exit

### Frontmatter Editing

- Parse and edit YAML, TOML, and JSON frontmatter
- **Two editing locations:**
  - Bottom panel (collapsible)
  - Inspector panel (right sidebar, ⌥⌘I)
- Structured form editor with fields for:
  - Title, Date, Draft status, Description
  - Tags and Categories (chip-based input with flow layout)
- Raw text editor for advanced editing
- Parse validation with error feedback
- Custom fields preserved
- Round-trip format preservation

### Inspector Panel (⌥⌘I)

- Right-side panel following macOS conventions
- Metadata section with frontmatter fields
- Statistics section with word/character counts
- Collapsible sections
- Persisted visibility state

### Navigation

- Breadcrumb navigation bar showing file path
- Click breadcrumb segments to navigate
- Quick Open (⌘P) for fuzzy file search (coming soon)

### Hugo Page Bundle Support

- Visual detection of page bundles (folders with index.md or _index.md)
- Distinct purple icon with gear badge
- "bundle" badge label for easy identification
- Click page bundle to automatically open its index file

### File Operations

- Save files (⌘S) with frontmatter + markdown combined
- Auto-save with configurable delay (default 2 seconds)
- Conflict detection - alerts if file modified externally
- Context menus for files and folders:
  - New Markdown File, New Folder
  - Duplicate, Move to Trash
  - Reveal in Finder, Copy Path
- Undo/redo support in editor
- Unsaved changes indicator

### Preferences (⌘,)

- **Editor tab:**
  - Font size (11-24pt)
  - Highlight current line toggle
- **Auto-Save tab:**
  - Enable/disable auto-save
  - Auto-save delay (1-10 seconds)

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘O | Open Hugo Site |
| ⌘S | Save current file |
| ⌘, | Open Preferences |
| ⌘1 | Editor only mode |
| ⌘2 | Preview only mode |
| ⌘3 | Split view mode |
| ⌥⌘I | Toggle Inspector |
| ⌃⌘F | Toggle Focus Mode |
| ⌘F | Focus search field |
| ⌘B | Bold selected text |
| ⌘I | Italic selected text |
| ⌘K | Insert link |
| ⌘⇧I | Insert image |
| ⌘' | Block quote |
| Esc | Exit Focus Mode / Clear search |

### Performance

- LRU content cache (20 files) for efficient memory usage
- File preloading for smooth transitions
- Optimized WKWebView with shared process pool
- Background file I/O with async/await

### Accessibility

- VoiceOver support throughout
- Reduce Motion preference respected
- Keyboard navigation for all features

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15+ (for development)
- Swift 5.9+

## Installation

### For Development

1. Clone the repository

2. Generate Xcode project (if needed):
   ```bash
   xcodegen generate
   ```

3. Open in Xcode:
   ```bash
   open Victor.xcodeproj
   ```

4. Build and run:
   - Select the "Victor" scheme
   - Select "My Mac" as the destination
   - Press ⌘R to build and run

### Alternative: Command Line Build

```bash
# Build with xcodebuild
xcodebuild -project Victor.xcodeproj -scheme Victor -configuration Debug build
```

## Usage

1. **Launch Victor**
2. **Open a site**: Click "Open Hugo Site" or use ⌘O (or select from Recent Sites)
3. **Navigate**: Browse the file tree, use search to filter
4. **Choose layout**: Use ⌘1/2/3 or the tab bar to switch between Editor/Preview/Split
5. **Edit**:
   - Edit markdown in the editor
   - Edit frontmatter in bottom panel or Inspector (⌥⌘I)
   - Use toolbar for formatting
6. **Focus**: Press ⌃⌘F for distraction-free writing
7. **Save**: Press ⌘S or let auto-save handle it

## Project Structure

```
Victor/
├── Models/              # Data models
│   ├── HugoSite.swift
│   ├── ContentFile.swift
│   ├── FileNode.swift
│   └── Frontmatter.swift
├── ViewModels/          # State management
│   ├── SiteViewModel.swift
│   └── EditorViewModel.swift
├── Views/
│   ├── MainWindow/      # Main app layout
│   │   ├── ContentView.swift
│   │   ├── SidebarView.swift
│   │   ├── FileListView.swift
│   │   ├── EditorPanelView.swift
│   │   ├── PreviewPanel.swift
│   │   ├── TabBarView.swift
│   │   ├── BreadcrumbBar.swift
│   │   └── FrontmatterBottomPanel.swift
│   ├── Editor/
│   │   ├── EditorTextView.swift
│   │   ├── EditorStatusBar.swift
│   │   └── FrontmatterEditorView.swift
│   ├── Preview/
│   │   └── PreviewWebView.swift
│   ├── Inspector/
│   │   └── InspectorPanel.swift
│   ├── FocusMode/
│   │   └── FocusModeView.swift
│   ├── Preferences/
│   │   └── PreferencesView.swift
│   └── Animations/
│       └── AnimationModifiers.swift
├── Services/
│   ├── FileSystemService.swift
│   ├── FrontmatterParser.swift
│   ├── MarkdownRenderer.swift
│   └── AutoSaveService.swift
├── AppConstants.swift
└── Resources/
    └── preview-styles.css
```

## Dependencies

- **Down** (0.11.0): Markdown to HTML conversion
- **Yams** (5.x): YAML frontmatter parsing
- **TOMLKit** (0.6.0): TOML frontmatter parsing

## Architecture

- **Pattern**: MVVM with `@Observable` (SwiftUI)
- **State Management**: `@MainActor` for thread-safe UI updates
- **File I/O**: Async/await with `NSFileCoordinator`
- **Security**: App Sandbox with security-scoped bookmarks
- **Caching**: LRU cache for content files with automatic eviction

## Future Enhancements

- File system watching with FSEvents for live reload
- Image asset management and drag & drop
- Syntax highlighting for code blocks
- Git integration for version control
- Hugo server integration for live preview
- Hugo feature integration - understand the Hugo site model and leverage it for a more integrated CMS
- Multi-file tabs

## Hugo Site Structure

Victor expects a standard Hugo site structure:

```
your-hugo-site/
├── content/           # Required: Markdown content files
│   ├── posts/
│   │   ├── post-1.md
│   │   └── post-2.md
│   └── about.md
├── config.toml        # Hugo configuration
├── static/            # Static assets
├── themes/            # Hugo themes
└── public/            # Generated site (ignored)
```

## Security & Privacy

Victor uses macOS App Sandbox for security:

- Only accesses folders you explicitly select
- Uses security-scoped bookmarks for persistent access
- Network access only for WebView preview rendering

## Troubleshooting

### "Selected folder does not appear to be a Hugo site"

- Ensure the folder has a `content/` directory or a config file
- Config files: `hugo.toml`, `config.toml`, `hugo.yaml`, `config.yaml`, etc.

### No files showing

- Check that the `content/` directory contains `.md` files
- Use the search bar to verify files are loaded

### Build errors

```bash
# Regenerate project
xcodegen generate

# Clean and rebuild
xcodebuild clean
xcodebuild -project Victor.xcodeproj -scheme Victor build
```

## Contributing

Contributions welcome for:

- Bug fixes and real-world testing
- UI/UX enhancements
- Documentation improvements
- Future enhancements (file watching, image drag & drop, Git integration, syntax highlighting)
- Additional Hugo-specific features
- Unit and integration tests

## License

[Specify your license here]

## Credits

Built with:

- SwiftUI (Apple)
- Down by John Nguyen
- Yams by JP Simard
- TOMLKit by LebJe

---

**Victor** - A modern Hugo CMS for macOS
