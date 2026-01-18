# Victor Code Review - Expert Panel Findings & Action Plan

**Date**: 2026-01-19
**Reviewers**: Security Expert, Architecture Expert, SwiftUI Expert, Code Quality Expert
**Codebase**: 91 Swift files, ~25k LOC

---

## Executive Summary

A comprehensive code review was conducted by a panel of specialized experts covering security, architecture, SwiftUI best practices, DRY principles, and magic numbers. The Victor codebase demonstrates **mature engineering practices** with proper concurrency handling, modern SwiftUI patterns, and thoughtful performance optimizations.

**Overall Assessment: B+ (85/100)**

Key strengths:
- Proper `@Observable` / `@MainActor` usage throughout
- Excellent race condition prevention in file switching
- Well-structured AppConstants for centralized configuration
- Clean separation of concerns between Views and ViewModels

Key areas for improvement:
- SiteViewModel has grown too large (1600+ lines)
- Security hardening needed for server code and web views
- Some magic numbers not yet centralized to AppConstants
- Accessibility labels missing on icon-only buttons

---

## Table of Contents

1. [Security Findings](#1-security-findings)
2. [Architecture Findings](#2-architecture-findings)
3. [SwiftUI Best Practices](#3-swiftui-best-practices)
4. [DRY & Magic Numbers](#4-dry--magic-numbers)
5. [Action Items by Priority](#5-action-items-by-priority)
6. [Implementation Estimates](#6-implementation-estimates)

---

## 1. Security Findings

**Security Rating: 8/10** (Excellent for a native app, minor improvements needed)

### HIGH Priority

#### SEC-1: Command Injection via Hugo Binary Path
- **File**: `Victor/Services/HugoServerService.swift:190-235`
- **Issue**: `findBinaryViaWhich()` returns paths without validating they're in expected locations. If path discovery were ever generalized to user input, this could enable command injection.
- **Fix**: Validate binary paths are within allowed prefixes (`/usr/local/bin/`, `/opt/homebrew/bin/`, `/usr/bin/`)

```swift
private func findBinaryViaWhich(_ binary: String) async -> String? {
    // Validate binary name (no shell metacharacters)
    let allowedPattern = /^[a-zA-Z0-9\-_]+$/
    guard binary.matches(of: allowedPattern).count == 1 else {
        Logger.shared.warning("Invalid binary name: \(binary)")
        return nil
    }

    // ... existing code ...

    if let path = output, !path.isEmpty {
        // Validate path is in expected locations
        let allowedPrefixes = ["/usr/local/bin/", "/opt/homebrew/bin/", "/usr/bin/"]
        guard allowedPrefixes.contains(where: { path.hasPrefix($0) }) else {
            Logger.shared.warning("Binary found in unexpected location: \(path)")
            return nil
        }
        return path
    }
}
```

#### SEC-2: Path Traversal in File Operations
- **File**: `Victor/Services/FileSystemService.swift:313-395`
- **Issue**: `createMarkdownFile()` and `renameFile()` don't validate that resulting paths stay within site boundaries. `../` sequences could escape.
- **Fix**: Add path validation helper

```swift
private func validatePathWithinSite(_ url: URL, siteRoot: URL) throws {
    let canonicalPath = url.standardized.path
    let canonicalSiteRoot = siteRoot.standardized.path
    guard canonicalPath.hasPrefix(canonicalSiteRoot) else {
        throw FileError.accessDenied
    }
}
```

#### SEC-3: Missing Content Security Policy in Preview
- **File**: `Victor/Views/Preview/PreviewWebView.swift:10-23`
- **Issue**: WKWebView loads user content without CSP or JavaScript restrictions. Malicious markdown could execute scripts.
- **Fix**: Disable JavaScript or add strict CSP

```swift
configuration.preferences.javaScriptEnabled = false
// OR add CSP via user script
```

### MEDIUM Priority

#### SEC-4: WebSocket Certificate Validation
- **File**: `Victor/Services/LiveReloadClient.swift:78-99`
- **Issue**: No certificate validation for WSS connections (currently localhost only, but should be hardened)

#### SEC-5: Missing App Sandbox
- **File**: `Victor/Victor.entitlements`
- **Issue**: App is not sandboxed. Consider adding for defense-in-depth.

### Positive Security Practices Observed
- Uses `executableURL` instead of deprecated `launchPath`
- Proper SIGTERM/SIGKILL shutdown sequence for processes
- Security-scoped bookmarks for persistent file access
- External links open in default browser (not in-app WebView)
- YAML normalization prevents type confusion

---

## 2. Architecture Findings

**Architecture Rating: B+ (85/100)**

### HIGH Priority

#### ARCH-1: SiteViewModel God Object
- **File**: `Victor/ViewModels/SiteViewModel.swift` (1622 lines)
- **Issue**: Handles too many responsibilities: site management, file selection, content caching, config loading, template management, archetypes, file operations, server coordination, search, and status tracking.
- **Fix**: Extract into focused components:
  - `FileNavigationViewModel` - file selection, tree navigation, search
  - `FileCacheManager` - LRU cache, content loading/eviction
  - `FileOperationsService` - rename, duplicate, trash operations
  - `SiteConfigurationViewModel` - Hugo config, data files, templates

#### ARCH-2: Singleton Dependency Injection
- **Files**: All services use `.shared` pattern (212 instances across 41 files)
- **Issue**: Hard to test, creates tight coupling
- **Fix**: Introduce protocol abstractions and dependency injection

```swift
protocol FileSystemServicing {
    func readContentFile(at url: URL) async throws -> ContentFile
}

final class FileSystemService: FileSystemServicing {
    static let shared: FileSystemServicing = FileSystemService()
}
```

#### ARCH-3: Model Classes Using @Observable
- **Files**: `Frontmatter.swift`, `FileNode.swift`, `HugoConfig.swift`, `ContentFile.swift`, `DataFile.swift`
- **Issue**: Models use reference semantics where value semantics would be safer
- **Fix**: Evaluate converting simple data containers to structs with Equatable

### MEDIUM Priority

#### ARCH-4: Service Singletons Inconsistent
- **Issue**: `HugoServerService` and `AutoSaveService` are actors, but other services are plain classes
- **Fix**: Document why each service is/isn't an actor, or standardize

#### ARCH-5: State Duplication
- **Files**: `SiteViewModel.swift:66-91`, `EditorViewModel.swift:16-28`
- **Issue**: Content stored in both SiteViewModel (`editedContentByFile`) and EditorViewModel (`localContent`)
- **Fix**: Document why dual storage is needed or consolidate

#### ARCH-6: Silent Error Swallowing
- **File**: `Victor/ViewModels/EditorViewModel.swift:220-224`
- **Issue**: Successful saves after file switch are silently ignored
- **Fix**: Add logging for successful saves even when not updating UI

### Positive Architecture Practices
- Excellent race condition prevention with nodeID validation
- LRU cache with proper eviction respecting unsaved changes
- Version counter for O(1) change detection
- Clean async/await patterns throughout

---

## 3. SwiftUI Best Practices

**SwiftUI Rating: A- (88/100)**

### HIGH Priority

#### UI-1: ConfigEditor Tabs in Single File
- **File**: `Victor/Views/ConfigEditor/ConfigEditorView.swift:196-453`
- **Issue**: ConfigEssentialsTab, ConfigContentTab, ConfigTaxonomiesTab, ConfigAdvancedTab all in same file
- **Fix**: Extract to `Views/ConfigEditor/Tabs/` directory

#### UI-2: List Performance in FileListView
- **File**: `Victor/Views/MainWindow/FileListView.swift:9-39`
- **Issue**: Entire list rebuilds on filteredNodes change
- **Fix**: Add `.equatable()` modifier to row views

```swift
FileRowView(viewModel: viewModel, node: node)
    .equatable()
    .tag(node.id)
```

#### UI-3: Heavy Computation in AssetBrowserView
- **File**: `Victor/Views/AssetBrowser/AssetBrowserView.swift:18-36`
- **Issue**: `filteredAssets` computed on every view update
- **Fix**: Move to `@State` with explicit `.onChange` triggers

#### UI-4: Missing Accessibility Labels
- **Files**: `EditorPanelView.swift:206-212`, `AssetBrowserView.swift:121-127`, `LivePreviewPanel.swift:67-95`
- **Issue**: Icon-only buttons lack accessibility labels
- **Fix**: Add `.accessibilityLabel()` to all icon buttons

```swift
ToolbarButton(icon: "bold", label: "Bold") { onFormat(.bold) }
    .accessibilityLabel("Apply bold formatting")
    .accessibilityHint("Formats selected text as bold")
```

#### UI-5: Search Debounce Too Aggressive
- **File**: `Victor/Views/GlobalSearch/GlobalSearchView.swift:105-107`
- **Issue**: 0.3s debounce may cause lag for large codebases
- **Fix**: Increase to 0.5s and add minimum query length (2 chars)

### MEDIUM Priority

#### UI-6: Missing Preview Providers
- **Files**: `DataFileEditorView.swift`, `FileListView.swift`, `EditorToolbar`
- **Issue**: Complex components lack preview providers
- **Fix**: Add comprehensive previews with edge cases

#### UI-7: Dynamic Type Support
- **Files**: Various - numeric font sizes used
- **Issue**: `.font(.system(size: 11))` doesn't scale with Dynamic Type
- **Fix**: Use semantic sizes: `.font(.system(.caption2))`

### Positive SwiftUI Practices
- Excellent use of `@Observable` and `@Bindable`
- Good use of `@ViewBuilder` for conditional rendering
- Proper focus management with `@FocusState`
- `reduceMotion` environment value respected

---

## 4. DRY & Magic Numbers

### AppConstants Usage

Victor has a well-structured `AppConstants.swift` with categories:
- `AutoSave` - debounce intervals
- `Preview` - preview timing
- `Timing` - UI feedback durations
- `Animation` - fast/standard/slow durations
- `Editor` - font size, padding
- `Sidebar` - min/ideal/max widths
- `Content` - panel widths
- `Window` - dimensions
- `Dialog` - shortcode picker sizes
- `Toolbar` - spacing, padding
- `GlobalSearch` - limits, dimensions
- `UserDefaultsKeys` - all UserDefaults keys

### Magic Numbers Still in Code

The following hardcoded values should be moved to AppConstants:

#### Layout Constants Not Yet Centralized

| File | Line | Value | Suggested Constant |
|------|------|-------|-------------------|
| `GlobalSearchView.swift` | 180 | `width: 100` | `GlobalSearch.scopePickerWidth` |
| `GlobalSearchView.swift` | 406 | `width: 40` | `GlobalSearch.lineNumberWidth` |
| `ConfigEditorView.swift` | 334 | `width: 120` | `ConfigEditor.labelWidth` |
| `NewContentView.swift` | 120 | `width: 450, height: 400` | `Dialog.newContentWidth/Height` |
| `MenuEntryEditor.swift` | 47 | `width: 60` | `Dialog.menuWeightWidth` |
| `MenuEntryEditor.swift` | 132 | `width: 400` | `Dialog.menuEditorWidth` |
| `CustomFieldEditor.swift` | 122 | `width: 100` | `Editor.fieldLabelWidth` |
| `CustomFieldEditor.swift` | 231 | `width: 400` | `Dialog.customFieldWidth` |
| `ShortcodeCardView.swift` | 77 | `width: 350` | `Dialog.shortcodeCardWidth` |
| `ContentPathAutocompleteField.swift` | 162 | `maxHeight: 250` | `Editor.autocompleteMaxHeight` |

#### Padding Values to Standardize

Currently, padding values like `6`, `8`, `12` are used inconsistently. Consider adding:

```swift
enum Spacing {
    static let small: CGFloat = 4
    static let medium: CGFloat = 8
    static let large: CGFloat = 12
    static let extraLarge: CGFloat = 16
}
```

### DRY Violations to Address

#### DRY-4: Parser Code Duplication (~600 lines) - HIGH PRIORITY
- **Files**: `FrontmatterParser.swift`, `DataFileParser.swift`, `HugoConfigParser.swift`
- **Issue**: TOML/YAML/JSON conversion logic duplicated across 3 parsers
- **Fix**: Create `Helpers/TOMLHelper.swift` and `Helpers/SerializationHelper.swift`
- **Source**: Docs/CODE-REVIEW.md

#### DRY-1: Repeated Empty State Views
- **Files**: Multiple views use similar empty state patterns
- **Fix**: Create `EmptyStateView` component

```swift
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        }
    }
}
```

#### DRY-2: Repeated Badge/Tag Styling
- **Files**: `GlobalSearchView.swift`, `ConfigEditorView.swift`, `ShortcodeCardView.swift`
- **Issue**: Similar `.padding(.horizontal, 6).padding(.vertical, 2).background(...)` patterns
- **Fix**: Create `BadgeStyle` view modifier

#### DRY-3: Repeated Form Section Styling
- **Files**: `FrontmatterEditorView.swift`, `ConfigEditorView.swift`, `DataFileEditorView.swift`
- **Issue**: Similar section header/content styling
- **Fix**: Create `FormSectionView` component

#### DRY-5: File Status Badge Duplication (~150 lines)
- **Files**: 10+ editor views with identical status circle patterns
- **Fix**: Create `Views/Components/FileStatusBadgeView.swift`
- **Source**: Docs/CODE-REVIEW.md

#### DRY-6: Labeled TextField Component (~50 locations)
- **Files**: 15+ tab/form files with repeated label+textfield pattern
- **Fix**: Create `Views/Components/LabeledTextField.swift`
- **Source**: Docs/CODE-REVIEW.md

#### DRY-7: SF Symbols Constants (~50 locations)
- **Files**: 50+ view files with string literals for SF Symbols
- **Fix**: Create `Extensions/Symbols.swift` enum
- **Source**: Docs/CODE-REVIEW.md

#### DRY-8: Text Style Modifiers (~100 locations)
- **Files**: 40+ view files with repeated `.foregroundStyle()` calls
- **Fix**: Create `Extensions/StyleModifiers.swift`
- **Source**: Docs/CODE-REVIEW.md

---

## 5. Action Items by Priority

### P0 - Critical (Fix This Sprint)

| ID | Category | Description | File(s) |
|----|----------|-------------|---------|
| SEC-1 | Security | Validate Hugo binary path locations | `HugoServerService.swift` |
| SEC-2 | Security | Add path traversal protection | `FileSystemService.swift` |
| SEC-3 | Security | Add CSP to preview WebView | `PreviewWebView.swift` |
| ARCH-6 | Architecture | Log successful saves after file switch | `EditorViewModel.swift` |

### P1 - High (Plan for Next Sprint)

| ID | Category | Description | File(s) |
|----|----------|-------------|---------|
| ARCH-1 | Architecture | Extract SiteViewModel responsibilities | `SiteViewModel.swift` |
| UI-1 | SwiftUI | Extract ConfigEditor tabs to files | `ConfigEditorView.swift` |
| UI-4 | SwiftUI | Add accessibility labels to icons | Multiple |
| DRY-1 | Code Quality | Create EmptyStateView component | New file |
| DRY-4 | Code Quality | Extract parser helpers (~600 lines) | 3 parser files |

### P2 - Medium (Backlog)

| ID | Category | Description | File(s) |
|----|----------|-------------|---------|
| ARCH-2 | Architecture | Add protocol abstractions for services | All services |
| ARCH-3 | Architecture | Evaluate struct vs class for models | Model files |
| UI-2 | SwiftUI | Add .equatable() to list rows | `FileListView.swift` |
| UI-3 | SwiftUI | Optimize AssetBrowserView filtering | `AssetBrowserView.swift` |
| UI-5 | SwiftUI | Adjust search debounce timing | `GlobalSearchView.swift` |
| DRY-2 | Code Quality | Create BadgeStyle modifier | New file |
| DRY-3 | Code Quality | Create FormSectionView | New file |
| DRY-5 | Code Quality | Create FileStatusBadgeView | New file |
| MN-1 | Constants | Centralize remaining magic numbers | `AppConstants.swift` |

### P3 - Low (Nice to Have)

| ID | Category | Description | File(s) |
|----|----------|-------------|---------|
| SEC-4 | Security | Add certificate validation for WSS | `LiveReloadClient.swift` |
| SEC-5 | Security | Consider app sandboxing | Entitlements |
| ARCH-4 | Architecture | Document service actor strategy | Documentation |
| ARCH-5 | Architecture | Document state duplication rationale | Documentation |
| UI-6 | SwiftUI | Add missing preview providers | Multiple |
| UI-7 | SwiftUI | Use semantic font sizes | Multiple |
| DRY-6 | Code Quality | Create LabeledTextField component | New file |
| DRY-7 | Code Quality | Create SF Symbols constants | New file |
| DRY-8 | Code Quality | Create text style modifiers | New file |

---

## 6. Implementation Estimates

### Quick Wins (< 2 hours each)
- ARCH-6: Add logging for successful saves
- UI-5: Adjust search debounce timing
- MN-1: Move remaining magic numbers to AppConstants

### Small Tasks (2-4 hours each)
- SEC-1: Binary path validation
- SEC-2: Path traversal protection
- SEC-3: WebView CSP
- UI-1: Extract ConfigEditor tabs
- DRY-1: Create EmptyStateView
- DRY-2: Create BadgeStyle modifier

### Medium Tasks (1-2 days each)
- UI-4: Accessibility labels audit and fix
- ARCH-2: Protocol abstractions for services
- ARCH-3: Evaluate struct conversions
- DRY-3: FormSectionView component
- DRY-4: Parser helpers extraction (2-3 days - largest DRY win)
- DRY-5: FileStatusBadgeView component

### Large Tasks (3-5 days each)
- ARCH-1: SiteViewModel extraction

---

## Appendix: Files Reviewed

### ViewModels (3 files, ~2,500 LOC)
- `SiteViewModel.swift` - 1,622 lines
- `EditorViewModel.swift` - 510 lines
- `TextEditorViewModel.swift` - 380 lines

### Services (15 files, ~4,500 LOC)
- `FileSystemService.swift`, `HugoServerService.swift`, `AutoSaveService.swift`
- `FrontmatterParser.swift`, `HugoConfigParser.swift`, `DataFileParser.swift`
- `MarkdownRenderer.swift`, `TemplateParser.swift`, `BuildErrorParser.swift`
- And 6 others

### Views (59 files, ~12,000 LOC)
- `ContentView.swift`, `SidebarView.swift`, `EditorPanelView.swift`
- `FrontmatterEditorView.swift`, `ConfigEditorView.swift`
- `AssetBrowserView.swift`, `GlobalSearchView.swift`
- And 52 others

### Models (19 files, ~3,000 LOC)
- `HugoSite.swift`, `ContentFile.swift`, `Frontmatter.swift`
- `FileNode.swift`, `FileType.swift`, `HugoConfig.swift`
- And 13 others

---

*Generated by Victor Code Review Panel - 2026-01-19*
