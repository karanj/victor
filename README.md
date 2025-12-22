# Victor - macOS Hugo CMS

A native macOS app built with SwiftUI that provides a sophisticated editing experience for Hugo static sites.

## Features

### ✅ Currently Available (Phases 1-3 Complete)

**Site Management:**
- Open and browse Hugo site folders
- Hierarchical file tree navigation with expand/collapse
- File search (recursive through folders)
- Security-scoped bookmarks for persistent folder access

**Markdown Editing:**
- Full-featured markdown editor with NSTextView
- Formatting toolbar (bold, italic, headings, lists, code blocks)
- Monospace font, disabled smart quotes for code-friendly editing
- Live HTML preview with GitHub-style rendering
- Debounced preview updates (300ms) for smooth typing
- Live preview toggle

**Frontmatter Editing:**
- Parse and edit YAML, TOML, and JSON frontmatter
- Structured form editor with fields for:
  - Title
  - Date (optional with checkbox toggle)
  - Draft status
  - Description
  - Tags (chip-based input with flow layout)
  - Categories (chip-based input)
- Custom fields preserved
- Round-trip format preservation (YAML stays YAML, etc.)
- Collapsible frontmatter editor UI

**File Operations:**
- Save files (⌘S) with frontmatter + markdown combined
- Undo/redo support in editor
- Unsaved changes indicator

### Coming Soon
- **Phase 4**: Hugo page bundle support (visual indicators, special handling)
- **Phase 5**: Auto-save, file watching, extended keyboard shortcuts, and UI polish

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15+ (for development)
- Swift 5.9+

## Installation

### For Development

1. Clone the repository:
   ```bash
   cd /Users/karan/Developer/macos/victor
   ```

2. Open in Xcode:
   ```bash
   open Victor.xcodeproj
   ```
   This will open the project in Xcode and automatically fetch dependencies.

3. Build and run:
   - Select the "Victor" scheme
   - Select "My Mac" as the destination
   - Press ⌘R to build and run

### Alternative: Command Line Build

```bash
# Build with xcodebuild
xcodebuild -project Victor.xcodeproj -scheme Victor -configuration Debug build

# Or use Swift Package Manager
swift build
swift run Victor
```

## Usage

1. **Launch Victor**
2. **Open a site**: Click "Open Hugo Site" or use ⌘O
3. **Select folder**: Choose your Hugo site root directory (containing `content/` and config files)
4. **Navigate**: Browse the hierarchical file tree, expand/collapse folders
5. **Search**: Use the search bar to filter files across all folders
6. **Edit**: Click a file to open it
   - Edit frontmatter in the structured form (top)
   - Edit markdown content in the editor (middle)
   - See live preview in the right panel (toggle with "Live Preview" button)
7. **Format**: Use toolbar buttons for bold, italic, headings, lists, code blocks
8. **Save**: Press ⌘S to save changes (frontmatter + markdown combined)

## Project Structure

```
Victor/
├── Models/              # Data models (HugoSite, ContentFile, etc.)
├── ViewModels/          # State management (SiteViewModel)
├── Views/               # SwiftUI views
│   ├── MainWindow/      # Main app layout
│   ├── Editor/          # Editor components (Phase 2+)
│   ├── Preview/         # Preview components (Phase 2+)
│   └── Components/      # Reusable UI components
├── Services/            # Business logic services
│   ├── FileSystemService.swift
│   ├── FrontmatterParser.swift (Phase 3)
│   ├── MarkdownRenderer.swift (Phase 2)
│   └── AutoSaveService.swift (Phase 5)
├── Extensions/          # Swift extensions
└── Resources/           # Assets and templates
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

## Development Roadmap

### ✅ Phase 1: Foundation (Complete - Dec 22, 2024)
- Basic app structure with MVVM architecture
- Folder selection with security-scoped bookmarks
- File system service with NSFileCoordinator
- NavigationSplitView layout

### ✅ Phase 2: Editor & Preview (Complete - Dec 22, 2024)
- NSTextView-based markdown editor with formatting toolbar
- WKWebView-based live preview with GitHub styling
- Debounced preview updates (300ms)
- Hierarchical file tree navigation

### ✅ Phase 3: Frontmatter Support (Complete - Dec 22, 2024)
- YAML/TOML/JSON frontmatter parsing (Yams, TOMLKit)
- Form-based frontmatter editor with structured fields
- Optional date field with toggle
- Tag/category input with chip UI
- Preserve original format on save
- Custom fields preserved

### 🔄 Phase 4: Hugo Page Bundle Support (Next)
- Visual indicators for page bundles (folders with index.md)
- Special handling when opening page bundles
- Bundle-aware navigation
- Note: Detection logic exists, UI integration needed

### 📋 Phase 5: Polish & Reliability
- Auto-save with 2-second debounce
- File system watching with FSEvents
- Conflict detection and resolution
- Extended keyboard shortcuts
- Comprehensive error handling
- Performance optimization for 500+ files

## Hugo Site Structure

Victor expects a standard Hugo site structure:

```
your-hugo-site/
├── content/           # Required: Markdown content files
│   ├── posts/
│   │   ├── post-1.md
│   │   └── post-2.md
│   └── about.md
├── config.toml        # Hugo configuration (or hugo.toml, config.yaml, etc.)
├── static/            # Static assets
├── themes/            # Hugo themes
└── public/            # Generated site (ignored)
```

## Keyboard Shortcuts

- **⌘O**: Open Hugo site folder
- **⌘S**: Save current file
- **⌘F**: Focus search (when site is open)
- **⌘W**: Close window
- **⌘B**: Bold selected text (in editor)
- **⌘I**: Italic selected text (in editor)

More shortcuts coming in Phase 5.

## Security & Privacy

Victor uses macOS App Sandbox for security:
- Only accesses folders you explicitly select
- Uses security-scoped bookmarks for persistent access
- No network access except for WebView preview (Phase 2+)

## Troubleshooting

### "Selected folder does not appear to be a Hugo site"
- Ensure the folder has a `content/` directory or a config file
- Config files: `hugo.toml`, `config.toml`, `hugo.yaml`, `config.yaml`, etc.

### No files showing
- Check that the `content/` directory contains `.md` files
- Use the search bar to verify files are loaded

### Build errors
```bash
# Clean build
swift package clean
swift build
```

## Contributing

Phases 1-3 are complete! The app is fully functional for editing Hugo sites. Contributions welcome for:
- Bug fixes and testing
- UI/UX improvements
- Documentation enhancements
- Phase 5 features (auto-save, file watching, etc.)
- Performance optimizations
- Accessibility improvements

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
