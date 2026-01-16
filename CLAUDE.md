# Victor - macOS Hugo CMS

Native macOS application (SwiftUI) serving as a CMS for Hugo static sites. Provides markdown editing with live preview, frontmatter editing, Hugo config GUI, asset management, and Hugo server integration.

**Status**: Production ready | **Build**: Clean | **Size**: 91 Swift files, ~25k LOC | **Updated**: 2026-01-16

## Technical Stack

- **Platform**: macOS 14.0+ (Sonoma)
- **Framework**: SwiftUI + AppKit (NSTextView, WKWebView)
- **Architecture**: MVVM with `@Observable`, `@MainActor`
- **Build**: XcodeGen (`project.yml` → `.xcodeproj`)
- **Dependencies**: Down (Markdown), Yams (YAML), TOMLKit (TOML)

## File Type Routing

| File Type | Editor/Viewer |
|-----------|---------------|
| Markdown (.md) | EditorPanelView + live preview + frontmatter |
| Images | ImageViewerPanel with zoom/pan |
| hugo.toml/yaml/json | ConfigEditorView (Form/Raw tabs) |
| data/*.yaml/json/toml | DataFileEditorView (dynamic fields) |
| i18n/*.yaml/json/toml | TranslationEditorView |
| layouts/, themes/ HTML | TemplateEditorView (Go syntax) |
| Other code files | TextEditorPanel |

Routing logic: `FileViewerRouter.swift`

## Code Structure

```
Victor/
├── Models/           # HugoSite, ContentFile, Frontmatter, FileNode, FileType (19 types)
├── ViewModels/       # SiteViewModel (global state), EditorViewModel, TextEditorViewModel
├── Services/         # FileSystemService, AutoSaveService (actor), HugoServerService (actor),
│                     # FrontmatterParser, HugoConfigParser, DataFileParser, MarkdownRenderer
├── Views/
│   ├── MainWindow/   # ContentView (NavigationSplitView), SidebarView, EditorPanelView
│   ├── Editor/       # EditorTextView (NSTextView wrapper), FrontmatterEditorView, Tabs/
│   ├── ConfigEditor/ # ConfigEditorView
│   ├── DataEditor/   # DataFileEditorView
│   ├── AssetBrowser/ # AssetBrowserView, AssetDetailPanel
│   ├── ServerControls/ # ServerControlView, ServerLogView
│   ├── Preview/      # PreviewWebView, LivePreviewPanel, BuildErrorOverlay
│   └── Viewers/      # FileViewerRouter, ImageViewerPanel, TextViewerPanel
└── VictorTests/      # 8 test files, 200+ tests
```

## Key Files

| File | Purpose |
|------|---------|
| `SiteViewModel.swift` | Global state: selected file, search, site tree |
| `EditorViewModel.swift` | Markdown editing, auto-save, frontmatter sync |
| `FileViewerRouter.swift` | Routes files to appropriate editor/viewer |
| `HugoServerService.swift` | Actor managing hugo server subprocess |
| `AutoSaveService.swift` | Actor for debounced saves with conflict detection |
| `FrontmatterParser.swift` | Parse/serialize YAML/TOML/JSON frontmatter |

## Development

```bash
xcodegen generate                    # Regenerate project after adding files
open Victor.xcodeproj                # Open in Xcode, Cmd+R to run
xcodebuild test -project Victor.xcodeproj -scheme Victor -destination 'platform=macOS'
```

**Conventions**:
- ViewModels: `@MainActor @Observable`
- File I/O: `async/await`
- Background work: `actor` (AutoSaveService, HugoServerService)
- Bindings: `@Bindable` for `@Observable` objects

## Critical Implementation Notes

### File Switching Race Conditions (Fixed)
EditorViewModel must capture content before async operations and validate nodeID in callbacks:
```swift
// Capture BEFORE async - don't read computed properties after await
let capturedContent = markdownContent
let capturedFrontmatter = frontmatter
// In callbacks: guard selectedNode?.id == nodeID else { return }
```

### Yams Type Normalization
Yams returns `Dictionary<AnyHashable, Any>` which can't serialize back. Must normalize:
```swift
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
    // ... handle arrays
}
```

### Boolean Serialization
Always include boolean fields (don't skip `false`):
```swift
dictionary["buildDrafts"] = config.buildDrafts  // Always include
```

### YAML Width
Use `width: -1` to prevent line wrapping in Yams serialization.

## Debugging

| Issue | Check |
|-------|-------|
| Config editor | Console logs `[HugoConfigParser]`, `[HugoConfig]` |
| File type not detected | `FileType.swift` extension mapping, `HugoSiteStructure.swift` |
| Assets not loading | Folder in static/ or assets/, `AssetService.swift` |
| File switching bugs | `EditorViewModelTests.swift`, nodeID validation in callbacks |

## Future Work

Feature requests and bugs are tracked in **beads** (`.beads/` directory). Run `bd list` or `bd ready` to see open issues.

## Project Docs

- `Docs/HUGO-SERVER-INTEGRATION.md` - Hugo server integration
- `Docs/DATA-ARCHETYPES-GUIDE.md` - Data files and archetypes
- `Docs/CODE-REVIEW-ISSUES.yaml` - Code review findings
