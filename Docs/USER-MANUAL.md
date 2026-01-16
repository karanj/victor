# Victor User Manual

A comprehensive guide to using Victor, the native macOS CMS for Hugo static sites.

## Table of Contents

- [Getting Started](#getting-started)
- [Site Navigation](#site-navigation)
- [Layout Modes](#layout-modes)
- [Markdown Editing](#markdown-editing)
- [Focus Mode](#focus-mode)
- [Frontmatter Editing](#frontmatter-editing)
- [Hugo Config Editor](#hugo-config-editor)
- [Asset Browser](#asset-browser)
- [Hugo Server & Live Preview](#hugo-server--live-preview)
- [Data & Archetypes](#data--archetypes)
- [Template Editing](#template-editing)
- [File Operations](#file-operations)
- [Preferences](#preferences)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Hugo Site Structure](#hugo-site-structure)
- [Troubleshooting](#troubleshooting)

---

## Getting Started

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

---

## Site Navigation

### File Browser
- Open and browse full Hugo sites (content, config, static, assets, layouts, data, themes)
- 19 file types supported with type-specific icons, colors, and Hugo role detection
- Hierarchical file tree navigation with expand/collapse
- File search (recursive through folders)
- Recent sites list for quick access
- Auto-restore last opened site on launch

### File Status Indicators
- Modified files show unsaved changes indicator
- Recently saved files are highlighted

### Hugo Page Bundles
- Visual detection of page bundles (folders with index.md or _index.md)
- Distinct purple icon with gear badge
- "bundle" badge label for easy identification
- Click page bundle to automatically open its index file

### Breadcrumb Navigation
- Navigation bar showing current file path
- Click breadcrumb segments to navigate up the tree
- Sidebar toggle (⌃⌘S) for more editing space

---

## Layout Modes

Victor offers three layout modes for editing:

| Mode | Shortcut | Description |
|------|----------|-------------|
| **Editor Mode** | ⌘1 | Full-width markdown editor |
| **Preview Mode** | ⌘2 | Full-width rendered preview |
| **Split Mode** | ⌘3 | Side-by-side editor and preview |

- Use the tab bar for easy mode switching
- Layout preference is persisted across sessions

---

## Markdown Editing

### Editor Features
- High-performance NSTextView-based editor
- Current line highlighting
- Word count, character count, and cursor position in status bar
- Monospace font with configurable size
- Live HTML preview with GitHub-style rendering
- Debounced preview updates (300ms) for smooth typing

### Formatting Toolbar

| Group | Controls |
|-------|----------|
| Text formatting | Bold (⌘B), Italic (⌘I) |
| Headings | Dropdown for H1-H6 |
| Lists | Bullet, Numbered |
| Block elements | Code, Quote (⌘') |
| Insert elements | Link (⌘K), Image (⌘⇧I) |

### Hugo Shortcodes
- Shortcode picker (⌘⇧K) with searchable list
- Built-in Hugo shortcodes (figure, highlight, ref, relref, etc.)
- Form-based parameter configuration
- Live preview of generated shortcode syntax

---

## Focus Mode

Access distraction-free writing with ⌃⌘F:

- Centered text with comfortable max-width
- Hidden sidebar, toolbar, and chrome
- Word count and scroll progress indicator
- Press **Escape** to exit

---

## Frontmatter Editing

Victor parses and edits YAML, TOML, and JSON frontmatter.

### Editing Locations
- **Bottom panel** (collapsible) - below the editor
- **Inspector panel** (⌥⌘I) - right sidebar

### Form Editor Tabs

| Tab | Fields |
|-----|--------|
| Essential | title, date, draft, description |
| Publishing | publish date, expiry date, last modified |
| SEO | summary, keywords, author |
| Menus | menu configuration |
| Advanced | type, layout, custom fields |

### Additional Features
- **Raw text editor** for advanced editing
- Tags and Categories with chip-based input and flow layout
- Parse validation with error feedback
- Custom fields preserved on save
- Round-trip format preservation (no data loss)

---

## Hugo Config Editor

Edit your Hugo configuration with a GUI or raw text.

### Form Editor Tabs

| Tab | Settings |
|-----|----------|
| Essentials | baseURL, title, theme, language |
| Content | pagination, summaries, taxonomies |
| Taxonomies | tags, categories, custom taxonomies |
| Advanced | build flags, output formats, custom params |

### Features
- Supports all Hugo config formats: **TOML**, **YAML**, and **JSON**
- Two-way sync between Form and Raw views (no data loss)
- Custom fields preserved during edits
- Validation and error feedback

---

## Asset Browser

Browse and insert assets from your Hugo site.

### Browsing
- Browse `static/` folder and `assets/` folder
- **Grid view** with image thumbnails and asset type icons
- **List view** with compact file listing
- Folder-specific browsing (shows only assets in selected folder)

### Asset Detail Panel
- Large preview for images
- File metadata (size, dimensions, type, dates)
- Quick actions:
  - Copy path
  - Copy shortcode
  - Reveal in Finder

### Inserting Assets
- **Drag-and-drop** insertion into markdown editor
- Supports images (PNG, JPG, GIF, SVG, WebP), PDFs, and other file types

---

## Hugo Server & Live Preview

Run Hugo's development server directly within Victor.

### Features
- Start/stop Hugo server from the toolbar
- Configure server settings (port, drafts, future posts, expired posts)
- Live preview panel showing your rendered site
- Build error overlay with clickable file paths
- Server log viewer for debugging

### Usage
1. Click the server control button in the toolbar
2. Configure settings if needed
3. Start the server
4. Toggle between Live Preview and Markdown Preview

---

## Data & Archetypes

### Data File Editor
For files in the `data/` directory:

- **Form View**: Dynamic field editing supporting dictionaries, arrays, and nested structures
- **Raw View**: Direct text editing with format preservation
- Supports YAML, TOML, and JSON formats
- Context menu: "New Data File..." to create new data files

### Archetype Manager
For content templates in `archetypes/`:

- Load content templates from `archetypes/` directory
- **New Content dialog** (⇧⌘N) for creating content from archetypes
- Variable substitution (title, date, etc.) during content creation
- Context menu: "New Content from Archetype..."

### Translation Editor
For `i18n/` files:

- Key-value editing interface
- Plural form support for internationalization
- Context menu: "New Translation File..."

---

## Template Editing

### Template Editor
For files in `layouts/` and `themes/` directories:

- Go template syntax highlighting (`{{ }}`, keywords, variables, strings)
- Metadata panel showing blocks, partials, functions, and variables used
- Support for all template types:
  - base, single, list, partial
  - shortcode, taxonomy, home

### Template Browser
- Navigate template hierarchy with type/directory/inheritance views
- Theme template support with theme name badges
- Opens when clicking `layouts/` or `themes/` directories

---

## File Operations

### Saving
- Manual save with ⌘S
- Auto-save with configurable delay (default 2 seconds)
- Frontmatter and markdown are combined automatically

### Conflict Detection
- Alerts if file is modified externally while editing
- Options: Keep Editing or Reload from Disk

### Context Menus
Right-click files and folders for:
- New Markdown File
- New Folder
- Duplicate
- Move to Trash
- Reveal in Finder
- Copy Path

### Editor Features
- Undo/redo support
- Unsaved changes indicator

---

## Preferences

Open with ⌘,

### General Tab
- Font size (11-24pt)
- Highlight current line toggle

### Appearance Tab
- Badge colors (Draft, Scheduled, Expired)
- Reset to defaults

### Auto-Save Tab
- Enable/disable auto-save
- Auto-save delay (1-10 seconds)

### Server Tab
- Hugo installation status
- Server configuration

---

## Keyboard Shortcuts

### General

| Shortcut | Action |
|----------|--------|
| ⌘O | Open Hugo Site |
| ⌘S | Save current file |
| ⌘, | Open Preferences |
| ⌘F | Focus search field |
| Esc | Exit Focus Mode / Clear search |

### Layout

| Shortcut | Action |
|----------|--------|
| ⌘1 | Editor only mode |
| ⌘2 | Preview only mode |
| ⌘3 | Split view mode |
| ⌥⌘I | Toggle Inspector |
| ⌃⌘S | Toggle Sidebar |
| ⌃⌘F | Toggle Focus Mode |

### Formatting

| Shortcut | Action |
|----------|--------|
| ⌘B | Bold selected text |
| ⌘I | Italic selected text |
| ⌘K | Insert link |
| ⌘⇧I | Insert image |
| ⌘⇧K | Open shortcode picker |
| ⌘' | Block quote |

### Content Creation

| Shortcut | Action |
|----------|--------|
| ⇧⌘N | New content from archetype |

---

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
└── public/            # Generated site (ignored by Victor)
```

Victor detects and provides appropriate editing capabilities for all Hugo directories and file types.

---

## Troubleshooting

### "Selected folder does not appear to be a Hugo site"

- Ensure the folder has a `content/` directory or a config file
- Valid config files: `hugo.toml`, `config.toml`, `hugo.yaml`, `config.yaml`, `hugo.json`, `config.json`

### No files showing in sidebar

- Check that the `content/` directory contains `.md` files
- Use the search bar to verify files are loaded
- Try closing and reopening the site

### Files not saving

- Check for conflict detection alerts
- Verify you have write permissions to the folder
- Check if the file is open in another application

### Live preview not working

- Ensure Hugo is installed (`hugo version` in Terminal)
- Check the Server tab in Preferences for Hugo status
- View server logs for error messages

### Performance issues

- Large sites (500+ files) may take a moment to load initially
- Close unused sites from Recent Sites
- Restart Victor if memory usage is high

---

## Security & Privacy

Victor uses macOS App Sandbox for security:

- Only accesses folders you explicitly select
- Uses security-scoped bookmarks for persistent access
- Network access only for WebView preview rendering
- No data is sent to external servers
