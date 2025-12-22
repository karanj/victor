# Victor - macOS Hugo CMS

A native macOS app built with SwiftUI that provides a sophisticated editing experience for Hugo static sites.

## Features

### Phase 1 (✅ Complete)
- Open and browse Hugo site folders
- File navigation with search
- Display markdown file contents
- Security-scoped bookmarks for persistent folder access
- Flat file list view

### Coming Soon
- **Phase 2**: Live markdown preview with WKWebView
- **Phase 3**: Frontmatter parsing and editing (YAML/TOML)
- **Phase 4**: Hierarchical file tree navigation
- **Phase 5**: Auto-save, file watching, and UI polish

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

1. Launch Victor
2. Click "Open Hugo Site" button or use ⌘O
3. Select your Hugo site root directory (the folder containing `content/` and config files)
4. Browse markdown files in the sidebar
5. Click on a file to view its contents
6. Use the search bar to filter files

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

### ✅ Phase 1: Foundation (Complete)
- Basic app structure
- Folder selection and browsing
- Simple file list view

### 🚧 Phase 2: Editor & Preview (Next)
- NSTextView-based markdown editor
- WKWebView-based live preview
- Debounced preview updates

### 📋 Phase 3: Frontmatter Support
- YAML/TOML/JSON frontmatter parsing
- Form-based frontmatter editor
- Preserve original format on save

### 📋 Phase 4: File Tree Navigation
- Hierarchical file browser
- Hugo page bundle support
- Folder expand/collapse

### 📋 Phase 5: Polish & Reliability
- Auto-save with conflict detection
- File system watching
- Keyboard shortcuts
- Error handling

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
- **⌘F**: Focus search (when site is open)
- **⌘W**: Close window

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

Phase 1 is complete. Check the roadmap above for upcoming features. Contributions welcome for:
- Bug fixes
- UI improvements
- Documentation
- Testing

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
