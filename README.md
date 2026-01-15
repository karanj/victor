# Victor - macOS Hugo CMS

A native macOS app built with SwiftUI that provides a sophisticated editing experience for Hugo static sites.

![Victor logo](Docs/Victor-logo.svg?raw=true)

![Screenshot of Victor in action](Docs/Victor-screenshot.png?raw=true "An example of Victor in use")

**Last Updated**: January 13, 2026
**Build Status**: Clean build, no errors, no warnings
**Code Quality**: All critical and high-priority issues fixed; macOS best practices reviewed
**Test Coverage**: 166 tests covering config, frontmatter, data files, and archetypes
**Architecture**: MVVM with @Observable, security-scoped bookmarks, actor-based auto-save
**Codebase**: 78 Swift files, ~20,000 lines of code

## Features

### Site Content Management

- Open and browse full Hugo sites (content, config, static, assets, layouts, data, themes)
- **19 file types** with type-specific icons, colors, and Hugo role detection
- Hierarchical file tree navigation with expand/collapse
- File search (recursive through folders)
- Security-scoped bookmarks for persistent folder access
- Recent sites list for quick access
- File status indicators (modified, recently saved)
- Hugo page bundle detection and visualization (purple icon with gear badge)
- Auto-restore last opened site on launch

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
- **Structured form editor** with 5 organized tabs:
  - Essential (title, date, draft, description)
  - Publishing (publish date, expiry date, last modified)
  - SEO (summary, keywords, author)
  - Menus (menu configuration)
  - Advanced (type, layout, custom fields)
- **Raw text editor** for advanced editing
- Tags and Categories with chip-based input and flow layout
- Parse validation with error feedback
- Custom fields preserved on save
- Round-trip format preservation (no data loss)

### Inspector Panel (⌥⌘I)

- Right-side panel following macOS conventions
- Metadata section with frontmatter fields
- Statistics section with word/character counts
- Collapsible sections
- Persisted visibility state

### Hugo Config Editor

- **GUI form editor** with 4 organized tabs:
  - Essentials (baseURL, title, theme, language)
  - Content (pagination, summaries, taxonomies)
  - Taxonomies (tags, categories, custom taxonomies)
  - Advanced (build flags, output formats, custom params)
- **Raw text editor** for direct config editing
- Supports all Hugo config formats: **TOML**, **YAML**, and **JSON**
- Two-way sync between Form and Raw views (no data loss)
- Custom fields preserved during edits
- Round-trip format preservation
- Validation and error feedback

### Asset Browser

- Browse static assets (`static/` folder) and page resources (`assets/` folder)
- **Grid view** with image thumbnails and asset type icons
- **List view** with compact file listing
- **Asset detail panel** showing:
  - Large preview for images
  - File metadata (size, dimensions, type, dates)
  - Quick actions (copy path, copy shortcode, reveal in Finder)
- **Drag-and-drop** insertion into markdown editor
- Folder-specific browsing (shows only assets in selected folder)
- Support for images (PNG, JPG, GIF, SVG, WebP), PDFs, and other file types

### Data & Archetypes Management

- **Data File Editor** for files in `data/` directory:
  - **Form View**: Dynamic field editing supporting dictionaries, arrays, and nested structures
  - **Raw View**: Direct text editing with format preservation
  - Supports YAML, TOML, and JSON formats
  - Context menu: "New Data File..." to create new data files

- **Archetype Manager**:
  - Load content templates from `archetypes/` directory
  - **New Content dialog** (⇧⌘N) for creating content from archetypes
  - Variable substitution (title, date, etc.) during content creation
  - Context menu: "New Content from Archetype..."

- **Translation Editor** for `i18n/` files:
  - Key-value editing interface
  - Plural form support for internationalization
  - Context menu: "New Translation File..."

### Template Editing

- **Template Editor** for files in `layouts/` and `themes/` directories:
  - Go template syntax highlighting (`{{ }}`, keywords, variables, strings)
  - Metadata panel showing blocks, partials, functions, and variables used
  - Support for all template types (base, single, list, partial, shortcode, taxonomy, home)

- **Template Browser**:
  - Navigate template hierarchy with type/directory/inheritance views
  - Theme template support with theme name badges
  - Opens when clicking `layouts/` or `themes/` directories

### Multi-File Viewing & Editing

Victor intelligently routes files to the appropriate viewer based on file type:

| File Type | Capability |
|-----------|------------|
| **Markdown** (.md) | Full editor with live preview and frontmatter editing |
| **Images** (.png, .jpg, .gif, .svg, .webp) | Image viewer with zoom/pan controls |
| **Hugo Config** (hugo.toml/yaml/json) | GUI form editor + raw text editing |
| **Code Files** (HTML, CSS, JS, TS, Go) | Syntax-aware text editor |
| **Data Files** (YAML, TOML, JSON in data/) | GUI form editor with dynamic fields |
| **Translation Files** (i18n/*.yaml/json/toml) | Key-value editor with plural support |
| **Templates** (HTML in layouts/ or themes/) | Template editor with Go syntax highlighting |
| **Other Files** | Open in default macOS application |

### Navigation

- Breadcrumb navigation bar showing file path
- Click breadcrumb segments to navigate
- Sidebar toggle (⌃⌘S) for more editing space
- View menu integration for UI controls
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
| ⌃⌘S | Toggle Sidebar |
| ⌃⌘F | Toggle Focus Mode |
| ⌘F | Focus search field |
| ⌘B | Bold selected text |
| ⌘I | Italic selected text |
| ⌘K | Insert link |
| ⌘⇧I | Insert image |
| ⌘⇧K | Open shortcode picker |
| ⌘' | Block quote |
| Esc | Exit Focus Mode / Clear search |

### Hugo Shortcodes

- Shortcode picker (⌘⇧K) with searchable list
- Built-in Hugo shortcodes (figure, highlight, ref, relref, etc.)
- Form-based parameter configuration
- Live preview of generated shortcode syntax

### Performance

- LRU content cache (20 files) for efficient memory usage
- File preloading for smooth transitions
- System-managed WKWebView process pooling (automatic in macOS 12+)
- Background file I/O with async/await
- Centralized logging with os.log integration

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
├── Models/              # Data models (14 files)
│   ├── HugoSite.swift
│   ├── HugoSiteStructure.swift
│   ├── HugoConfig.swift
│   ├── ContentFile.swift
│   ├── TextFile.swift
│   ├── DataFile.swift
│   ├── Archetype.swift
│   ├── Template.swift
│   ├── Asset.swift
│   ├── FileNode.swift
│   ├── FileType.swift
│   ├── Frontmatter.swift
│   ├── FrontmatterTypes.swift
│   └── HugoShortcode.swift
├── ViewModels/          # State management (3 files)
│   ├── SiteViewModel.swift
│   ├── EditorViewModel.swift
│   └── TextEditorViewModel.swift
├── Views/               # ~48 files
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
│   │   ├── FrontmatterEditorView.swift
│   │   ├── TextEditorPanel.swift
│   │   ├── ShortcodePickerView.swift
│   │   ├── ShortcodeFormView.swift
│   │   ├── Components/          # Reusable components
│   │   └── Tabs/                # Frontmatter tab views
│   ├── ConfigEditor/
│   │   └── ConfigEditorView.swift
│   ├── DataEditor/
│   │   ├── DataFileEditorView.swift
│   │   └── NewDataFileView.swift
│   ├── NewContent/
│   │   └── NewContentView.swift
│   ├── TranslationEditor/
│   │   ├── TranslationEditorView.swift
│   │   └── NewTranslationFileView.swift
│   ├── TemplateEditor/
│   │   ├── TemplateEditorView.swift
│   │   ├── TemplateMetadataPanel.swift
│   │   └── TemplateBrowserView.swift
│   ├── AssetBrowser/
│   │   ├── AssetBrowserView.swift
│   │   └── AssetDetailPanel.swift
│   ├── Viewers/
│   │   ├── FileViewerRouter.swift
│   │   ├── ImageViewerPanel.swift
│   │   ├── TextViewerPanel.swift
│   │   └── UnsupportedFilePanel.swift
│   ├── Preview/
│   │   └── PreviewWebView.swift
│   ├── Inspector/
│   │   ├── InspectorPanel.swift
│   │   ├── MetadataSection.swift
│   │   └── StatisticsSection.swift
│   ├── FocusMode/
│   │   └── FocusModeView.swift
│   ├── Preferences/
│   │   └── PreferencesView.swift
│   └── Animations/
│       └── AnimationModifiers.swift
├── Services/            # 9 files
│   ├── FileSystemService.swift
│   ├── FrontmatterParser.swift
│   ├── HugoConfigParser.swift
│   ├── DataFileParser.swift
│   ├── ArchetypeManager.swift
│   ├── TemplateParser.swift
│   ├── AssetService.swift
│   ├── MarkdownRenderer.swift
│   ├── AutoSaveService.swift
│   └── Logger.swift
├── AppConstants.swift
└── Resources/
    └── preview-styles.css

VictorTests/             # 5 files
├── HugoConfigParserTests.swift   # Hugo config parsing tests (61 tests)
├── FrontmatterParserTests.swift  # Frontmatter parsing tests (60 tests)
├── DataFileParserTests.swift     # Data file parsing tests (22 tests)
├── ArchetypeManagerTests.swift   # Archetype processing tests (23 tests)
└── FileStatusMetadataTests.swift # File status metadata tests
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

## Testing

Victor includes a test suite covering critical parsing functionality:

### Running Tests

```bash
# Run all tests
xcodebuild test -project Victor.xcodeproj -scheme Victor

# Run specific test suite
xcodebuild test -project Victor.xcodeproj -scheme Victor -only-testing:VictorTests/HugoConfigParserTests
xcodebuild test -project Victor.xcodeproj -scheme Victor -only-testing:VictorTests/FrontmatterParserTests
```

### Test Coverage

| Test Suite | Tests | Description |
|------------|-------|-------------|
| HugoConfigParserTests | 61 | Hugo config parsing and serialization (TOML, YAML, JSON) |
| FrontmatterParserTests | 60 | Frontmatter parsing for markdown files |
| DataFileParserTests | 22 | Data file parsing and serialization |
| ArchetypeManagerTests | 23 | Archetype loading and template processing |

**HugoConfigParserTests** covers:
- Round-trip serialization for all formats (TOML, YAML, JSON)
- Error handling for invalid input
- Edge cases (empty configs, special characters, Unicode)
- Hugo-specific features (theme arrays, menus, taxonomies, build flags)
- Type handling (integers, floats, booleans, arrays)
- Custom field preservation
- Format detection from filenames

**FrontmatterParserTests** covers:
- Parsing all frontmatter formats (YAML `---`, TOML `+++`, JSON `{}`)
- All Hugo frontmatter fields (title, date, draft, tags, categories, etc.)
- Menu configurations and nested structures
- SEO fields, publishing dates, and layout options
- Round-trip serialization
- Error handling and edge cases

**DataFileParserTests** covers:
- Parsing YAML, TOML, and JSON data files
- Nested dictionary and array structures
- Round-trip serialization
- Error handling for malformed input

**ArchetypeManagerTests** covers:
- Loading archetypes from directory
- Variable substitution (title, date, etc.)
- Default archetype handling
- Content generation from templates

## Future Enhancements

### Planned Features

- **File system watching** with FSEvents for automatic reload when files change externally
- **Syntax highlighting** for code blocks in markdown preview
- **Git integration** for version control (status, commit, push)
- **Hugo server integration** for true live preview via `hugo server`
- **Multi-file tabs** for editing multiple files simultaneously
- **Search & replace** across multiple files
- **Custom themes** and color schemes for the editor
- **VoiceOver improvements** for enhanced accessibility

### Completed Features (Previously Planned)

✅ Image asset management and drag & drop
✅ Hugo config GUI editor
✅ Multi-file type support (view/edit images, code files, data files)
✅ File type detection and routing
✅ Asset browser with thumbnails
✅ Data files management (GUI for editing `data/` directory)
✅ Archetype management (create content from templates)
✅ Template editing with Go syntax highlighting
✅ Translation file editor for i18n

## Hugo Site Structure

Victor supports the complete Hugo site structure:

```
your-hugo-site/
├── content/           # Markdown content files
│   ├── posts/
│   │   ├── post-1.md
│   │   └── my-bundle/     # Page bundle
│   │       ├── index.md
│   │       └── image.jpg
│   └── about.md
├── config.toml        # Hugo configuration (or hugo.toml, config.yaml, etc.)
├── static/            # Static assets (served as-is)
│   └── images/
├── assets/            # Asset processing pipeline
├── layouts/           # Custom templates
├── themes/            # Hugo themes
├── data/              # Data files (YAML, TOML, JSON)
├── archetypes/        # Content templates
└── public/            # Generated site (ignored)
```

Victor detects and provides appropriate editing capabilities for all Hugo directories and file types.

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
- Future enhancements (file watching, Git integration, syntax highlighting, Hugo server integration)
- Accessibility improvements (VoiceOver, keyboard navigation)
- Expanding test coverage (ViewModels, Services, integration tests)
- Performance optimizations

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
