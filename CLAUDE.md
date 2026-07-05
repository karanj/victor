# Victor - macOS Hugo CMS

Native macOS application (SwiftUI) serving as a CMS for Hugo static sites. Provides markdown editing with live preview, frontmatter editing, Hugo config GUI, asset management, and Hugo server integration.

**Status**: Production ready | **Build**: Clean | **Size**: 91 Swift files, ~25k LOC | **Updated**: 2026-07-03

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

### Content State Dual Storage
Content is stored in two places for file switching without data loss:

| Location | Purpose |
|----------|---------|
| `SiteViewModel.editedContentByFile: [UUID: String]` | Persists edits when switching between files |
| `EditorViewModel.localContent: String` | Active editing state, bound to NSTextView |

**Sync Flow**:
1. File selected → `EditorViewModel.localContent` initialized from `SiteViewModel` (or file if no cached edits)
2. User edits → `localContent` updates → synced back to `SiteViewModel.editedContentByFile`
3. File switch → current `localContent` persisted to `editedContentByFile` before loading new file
4. Save → content written to disk, `editedContentByFile` entry cleared

**Source of truth**: `EditorViewModel.localContent` during active editing; `SiteViewModel.editedContentByFile` when file is not actively edited.

### Service Concurrency Strategy
Services use different patterns based on their state and access patterns:

| Service | Pattern | Rationale |
|---------|---------|-----------|
| `HugoServerService` | `actor` | Manages process lifecycle, output buffering - mutable state with concurrent access |
| `AutoSaveService` | `actor` | Debounce timers, pending save tracking - mutable state modified from multiple call sites |
| `FileSystemService` | `class` + `@MainActor` methods | Stateless operations, but some methods update UI-bound data |
| Parsers (Frontmatter, Config, Data) | `class` with static `shared` | Stateless, thread-safe parsing operations |
| `AssetService` | `class` with static `shared` | Mostly reads with cached thumbnails - cache is thread-safe via actor isolation |

**When to use `actor`**: Service has mutable state accessed from multiple concurrent contexts (timers, callbacks, async operations).

**When `@MainActor` methods suffice**: Service is stateless but needs to update `@Observable` models or UI state.

**Dependency injection (victor-zw4, done):** `FileSystemService`, `AutoSaveService`, and `HugoServerService` — the three services tests actually need isolated instances of — are injectable via initializer parameters defaulting to `.shared` (e.g. `init(fileSystemService: FileSystemService = .shared)`), stored as `let`. Each has a non-private `init()` (all three are side-effect-free to construct) so tests can pass a fresh instance instead of the process-wide singleton — critical for `AutoSaveService`/`HugoServerService` since they're actors with mutable state that would otherwise leak between tests. `SiteViewModel` holds `fileSystemService`/`hugoServerService` as non-private `let`s (not `private`) so views that already hold a `siteViewModel` reference (`ServerControlView`, `LivePreviewPanel`, `EditorTextView`'s Coordinator) thread the same instance through instead of reaching `.shared` directly; `EditorViewModel`/`TextEditorViewModel` take their own injected service directly. Views with no such seam (`ServerLogView` — separate `Window` scene, no `SiteViewModel`; `PreferencesView` — zero-arg `Settings` scene) keep `.shared`, since threading an instance through would require adding SwiftUI Environment plumbing solely for that one call site — a cost the design explicitly avoids. No protocol abstraction: the win is instance isolation, not behavioral fakes. Stateless parsers, `AssetService`, `NotificationService`, and `LiveReloadClient` are unaffected and keep plain `static let shared`.

### Model Type Strategy (Struct vs Class)

Models use `@Observable class` pattern by design. Evaluation of struct alternatives:

| Model | Pattern | Rationale |
|-------|---------|-----------|
| `Frontmatter` | class | 30+ mutable fields, `@Bindable` in 7+ views, version tracking for change detection |
| `FileNode` | class | Tree structure with `weak var parent`, recursive child relationships require reference semantics |
| `HugoConfig` | class | Form-bound editing via `@Bindable`, implements `EditableFile: AnyObject` protocol |
| `DataFile` | class | Form-bound editing, `EditableFile` protocol, change tracking via `originalContent` comparison |
| `ContentFile` | class | Contains `Frontmatter` reference, assigned to `FileNode.contentFile` for shared access |

**Why classes are appropriate here:**
1. **SwiftUI Binding**: `@Bindable` requires `@Observable` which works with classes. Form editors use two-way binding extensively.
2. **Shared Mutation**: Models are mutated from multiple locations (form fields, raw editor sync, auto-save). Reference semantics ensure all observers see the same state.
3. **Protocol Constraints**: `EditableFile` requires `AnyObject` for type-erased storage in dictionaries and generic handling.
4. **Tree Structures**: `FileNode` needs parent-child references that would cause copy-on-write issues with structs.

**Struct alternatives considered:**
- `FrontmatterSnapshot` already exists as an immutable struct for change detection - this is the appropriate pattern for value-type needs.
- `HugoMenuItem` is a struct because it's a simple data container without binding requirements.

## Debugging

| Issue | Check |
|-------|-------|
| Config editor | Console logs `[HugoConfigParser]`, `[HugoConfig]` |
| File type not detected | `FileType.swift` extension mapping, `HugoSiteStructure.swift` |
| Assets not loading | Folder in static/ or assets/, `AssetService.swift` |
| File switching bugs | `EditorViewModelTests.swift`, nodeID validation in callbacks |

## Outstanding Work

Open issues are tracked in `Docs/ISSUES.yaml` (structured YAML, 34 open tickets). Key areas:
- **Active program**: Mac polish + modernisation — design in `Docs/MAC-POLISH-DESIGN.md`, phased subagent execution plan in `Docs/MAC-POLISH-IMPLEMENTATION-PLAN.md` (Phase 0 = settings layer + strict-concurrency baseline)
- **P2**: Settings layer (victor-stn), Swift 6 strict concurrency burn-down (victor-sc6, 103 warnings), AsyncStream observation (victor-str), DI for fakeable services (victor-zw4, re-scoped), FSEvents file watching (9 tickets, dependency chain)
- **P3**: Git integration (6 tickets), preview syntax highlighting, Hugo theme CSS, editor Unicode-safety (victor-u16), cache eviction wiring (victor-lru), Task.detached audit (victor-tdt)
- **P4**: VoiceOver audit, code-health leftovers from the 2026-07-03 analysis (see `Docs/CODE-ANALYSIS-2026-07-03.md`), modernisation grab-bag (victor-mod)

To find work ready to start: look for `status: open` (no blockers). `status: blocked` tickets list their `blocked_by` dependencies.

## Project Docs

- `Docs/ISSUES.yaml` - Issue tracker (open work items)
- `Docs/CODE-REVIEW-PLAN.md` - Code review findings and status
- `Docs/CODE-ANALYSIS-2026-07-03.md` - Critical analysis session: 10 fixes (data loss, hang, dead prefs) + leftovers
- `Docs/MAC-POLISH-DESIGN.md` - Mac polish design: window chrome, menus, system integration, modernisation track (approved 2026-07-04)
- `Docs/MAC-POLISH-IMPLEMENTATION-PLAN.md` - Phased subagent orchestration plan for the above
- `Docs/HUGO-SERVER-INTEGRATION.md` - Hugo server integration
- `Docs/DATA-ARCHETYPES-GUIDE.md` - Data files and archetypes
- `Docs/TODO.md` - Detailed ticket descriptions (reference/archive)
