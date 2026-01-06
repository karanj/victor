# Victor Full-Site Hugo CMS Extension Plan

## Overview

Transform Victor from a content-only markdown editor into a comprehensive Hugo site CMS that can display, view, and edit all site files while providing a discoverable GUI for Hugo configuration.

**Current State:** Victor only scans `content/` directory and displays `.md` files
**Target State:** Full site visibility with file-type-aware viewing/editing and GUI config management

---

## Progress Summary

| Phase | Status | Completed Date |
|-------|--------|----------------|
| Phase 1: File Type Infrastructure | ✅ COMPLETE | 2025-12-30 |
| Phase 2: Multi-File Viewing | ✅ COMPLETE | 2025-12-30 |
| Phase 3: Text File Editing | ✅ COMPLETE | 2025-12-30 |
| Phase 4: Hugo Config GUI Editor | ✅ COMPLETE | 2025-12-31 |
| Phase 5: Data & Archetypes Management | ⏳ NOT STARTED | - |
| Phase 6: Asset Management | ✅ COMPLETE | 2026-01-01 |
| Phase 7: Template Editing | ⏳ NOT STARTED | - |
| Phase 8: Hugo Server Integration | ⏳ NOT STARTED | - |

### Completed Files Summary

**Phase 1:** FileType.swift, HugoSiteStructure.swift, modified FileNode/FileSystemService/FileListView

**Phase 2:** FileViewerRouter.swift, ImageViewerPanel.swift, TextViewerPanel.swift, UnsupportedFilePanel.swift, modified ContentView

**Phase 3:** TextFile.swift, TextEditorViewModel.swift, TextEditorPanel.swift, modified FileNode/SiteViewModel

**Phase 4:** HugoConfig.swift, HugoConfigParser.swift, ConfigEditorView.swift (with 4 tabs + raw view), modified SiteViewModel/FileViewerRouter

**Phase 6:** Asset.swift, AssetService.swift, AssetBrowserView.swift, AssetDetailPanel.swift, modified FileViewerRouter/EditorTextView (drag-drop support)

### Key Implementation Notes

**TOML Parsing (Phase 4):** TOMLKit returns `TOMLValue` wrapper types. Must use `tomlValue.string`, `tomlValue.bool`, etc. to extract values. See `HugoConfigParser.convertTOMLValue()`.

**Theme Array Support:** Hugo supports `theme: "name"` (string) or `theme: [name1, name2]` (array). `HugoConfig.themeIsArray` flag preserves original format on save.

---

## Important Context for Implementers

### Project Structure
```
/Users/karan/Developer/macos/victor/
├── Victor/
│   ├── Models/           # Data models (@Observable classes)
│   ├── ViewModels/       # Business logic (@MainActor @Observable)
│   ├── Views/            # SwiftUI views
│   │   ├── MainWindow/   # Main app layout views
│   │   ├── Editor/       # Editor-related views
│   │   ├── Preview/      # Preview panel views
│   │   └── Preferences/  # Settings views
│   ├── Services/         # File I/O, parsing, etc.
│   └── AppConstants.swift
├── project.yml           # XcodeGen configuration
└── Victor.xcodeproj/     # Generated (don't edit directly)
```

### Key Patterns Used in This Codebase

1. **All ViewModels use `@MainActor @Observable`** - This ensures UI updates happen on the main thread
2. **File I/O uses `async/await` with `Task.detached`** - Heavy operations run on background threads
3. **Views use `@Bindable`** to connect to `@Observable` objects
4. **After adding new files, run `xcodegen generate`** to update the Xcode project
5. **Build with:** `xcodebuild -project Victor.xcodeproj -scheme Victor build`

### Existing Key Files You'll Work With

| File | Purpose |
|------|---------|
| `Victor/Models/FileNode.swift` | Tree node for file browser |
| `Victor/Models/ContentFile.swift` | Markdown file with frontmatter |
| `Victor/Services/FileSystemService.swift` | All file operations |
| `Victor/ViewModels/SiteViewModel.swift` | Global app state |
| `Victor/Views/MainWindow/ContentView.swift` | Main three-column layout |
| `Victor/Views/MainWindow/FileListView.swift` | Sidebar file tree |
| `Victor/Views/MainWindow/EditorPanelView.swift` | Markdown editor panel |

---

## Phase 1: File Type Infrastructure (Foundation) ✅ COMPLETE

Phase 1 has been implemented. The following files were created/modified:

### Files Created
- `Victor/Models/FileType.swift` - Enum with 19 file types, icons, colors
- `Victor/Models/HugoSiteStructure.swift` - Hugo site detection logic

### Files Modified
- `Victor/Models/FileNode.swift` - Added `fileType`, `hugoRole`, `isConfigFile`, `isEditable`
- `Victor/Services/FileSystemService.swift` - Now scans entire site, not just `content/`
- `Victor/Views/MainWindow/FileListView.swift` - File type icons and colors

---

## Phase 2: Multi-File Viewing (Read Support) ✅ COMPLETE

### Goal
Enable viewing of all file types with appropriate viewers. Hide the preview panel for non-markdown files.

### Prerequisites
- Phase 1 must be complete
- Understand how `ContentView.swift` routes to `EditorPanelView`

---

### Step 2.1: Create the Image Viewer Panel

**Create new file:** `Victor/Views/Viewers/ImageViewerPanel.swift`

This view displays images with zoom and pan capabilities.

```swift
import SwiftUI
import AppKit

/// Panel for viewing image files
struct ImageViewerPanel: View {
    let url: URL

    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var zoomLevel: Double = 1.0

    // Zoom range
    private let minZoom: Double = 0.1
    private let maxZoom: Double = 5.0

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            imageToolbar

            Divider()

            // Image content
            if isLoading {
                ProgressView("Loading image...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let image = image {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomLevel)
                        .frame(
                            width: image.size.width * zoomLevel,
                            height: image.size.height * zoomLevel
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            await loadImage()
        }
    }

    private var imageToolbar: some View {
        HStack {
            // File name
            Text(url.lastPathComponent)
                .font(.headline)

            Spacer()

            // Image dimensions (if loaded)
            if let image = image {
                Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 20)

            // Zoom controls
            Button {
                zoomLevel = max(minZoom, zoomLevel - 0.25)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(zoomLevel <= minZoom)

            Text("\(Int(zoomLevel * 100))%")
                .frame(width: 50)
                .font(.caption.monospacedDigit())

            Button {
                zoomLevel = min(maxZoom, zoomLevel + 0.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(zoomLevel >= maxZoom)

            Button {
                zoomLevel = 1.0
            } label: {
                Text("100%")
                    .font(.caption)
            }

            Divider()
                .frame(height: 20)

            // Open in external app
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .help("Open in Preview")

            // Reveal in Finder
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func loadImage() async {
        isLoading = true
        errorMessage = nil

        do {
            // Load image on background thread
            let loadedImage = try await Task.detached {
                guard let image = NSImage(contentsOf: url) else {
                    throw ImageError.failedToLoad
                }
                return image
            }.value

            await MainActor.run {
                self.image = loadedImage
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load image: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
}

enum ImageError: LocalizedError {
    case failedToLoad

    var errorDescription: String? {
        switch self {
        case .failedToLoad:
            return "Could not load the image file."
        }
    }
}
```

---

### Step 2.2: Create the Text Viewer Panel

**Create new file:** `Victor/Views/Viewers/TextViewerPanel.swift`

This view displays text files (YAML, TOML, JSON, HTML, CSS, JS) in read-only mode initially.

```swift
import SwiftUI
import AppKit

/// Panel for viewing text files (read-only initially, editable in Phase 3)
struct TextViewerPanel: View {
    let url: URL
    let fileType: FileType

    @State private var content: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            textToolbar

            Divider()

            // Content
            if isLoading {
                ProgressView("Loading file...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .task {
            await loadContent()
        }
    }

    private var textToolbar: some View {
        HStack {
            // File type icon
            Image(systemName: fileType.systemImage)
                .foregroundStyle(fileType.defaultColor)

            // File name
            Text(url.lastPathComponent)
                .font(.headline)

            // File type badge
            Text(fileType.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.2))
                .cornerRadius(4)

            Spacer()

            // Line count
            if !content.isEmpty {
                let lineCount = content.components(separatedBy: .newlines).count
                Text("\(lineCount) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 20)

            // Open in external editor
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .help("Open in default app")

            // Reveal in Finder
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")

            // Copy path
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(url.path, forType: .string)
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .help("Copy file path")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func loadContent() async {
        isLoading = true
        errorMessage = nil

        do {
            let loadedContent = try await Task.detached {
                try String(contentsOf: url, encoding: .utf8)
            }.value

            await MainActor.run {
                self.content = loadedContent
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load file: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
}
```

---

### Step 2.3: Create the Unsupported File Panel

**Create new file:** `Victor/Views/Viewers/UnsupportedFilePanel.swift`

This view displays file info for binary/unsupported files.

```swift
import SwiftUI
import AppKit

/// Panel shown for unsupported file types
struct UnsupportedFilePanel: View {
    let url: URL
    let fileType: FileType

    @State private var fileSize: String = "Unknown"
    @State private var modificationDate: String = "Unknown"

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // File icon
            Image(systemName: fileType.systemImage)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            // File name
            Text(url.lastPathComponent)
                .font(.title2)
                .fontWeight(.medium)

            // File info
            VStack(spacing: 8) {
                HStack {
                    Text("Type:")
                        .foregroundStyle(.secondary)
                    Text(fileType.displayName)
                }
                HStack {
                    Text("Size:")
                        .foregroundStyle(.secondary)
                    Text(fileSize)
                }
                HStack {
                    Text("Modified:")
                        .foregroundStyle(.secondary)
                    Text(modificationDate)
                }
            }
            .font(.callout)

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open in Default App", systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            loadFileInfo()
        }
    }

    private func loadFileInfo() {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)

            // File size
            if let size = attributes[.size] as? Int64 {
                fileSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }

            // Modification date
            if let date = attributes[.modificationDate] as? Date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                modificationDate = formatter.string(from: date)
            }
        } catch {
            // Keep defaults
        }
    }
}
```

---

### Step 2.4: Create the File Viewer Router

**Create new file:** `Victor/Views/Viewers/FileViewerRouter.swift`

This view routes to the appropriate viewer based on file type.

```swift
import SwiftUI

/// Routes to the appropriate viewer/editor based on file type
struct FileViewerRouter: View {
    let node: FileNode
    @Bindable var siteViewModel: SiteViewModel
    @Bindable var editorViewModel: EditorViewModel

    var body: some View {
        Group {
            if node.isDirectory {
                // Directories shouldn't reach here, but handle gracefully
                directoryPlaceholder
            } else {
                switch node.fileType {
                case .markdown:
                    // Use existing markdown editor for markdown files in content/
                    if let contentFile = node.contentFile {
                        EditorPanelView(
                            siteViewModel: siteViewModel,
                            editorViewModel: editorViewModel,
                            contentFile: contentFile
                        )
                    } else {
                        // Markdown file not in content/ - show as text
                        TextViewerPanel(url: node.url, fileType: node.fileType)
                    }

                case .image:
                    ImageViewerPanel(url: node.url)

                case .yaml, .toml, .json, .html, .css, .javascript, .typescript,
                     .scss, .sass, .less, .xml, .go, .plainText:
                    TextViewerPanel(url: node.url, fileType: node.fileType)

                case .video, .audio, .pdf, .binary:
                    UnsupportedFilePanel(url: node.url, fileType: node.fileType)
                }
            }
        }
    }

    private var directoryPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Select a file to view")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

---

### Step 2.5: Update ContentView to Use FileViewerRouter

**Modify file:** `Victor/Views/MainWindow/ContentView.swift`

You need to find the section where `EditorPanelView` is used and replace it with `FileViewerRouter`, and hide the preview panel for non-markdown files.

First, read the current ContentView.swift to understand its structure, then make these changes:

**Key changes needed:**

1. Replace direct `EditorPanelView` usage with `FileViewerRouter`
2. Only show preview panel when `selectedNode?.fileType == .markdown`
3. For non-markdown files, force editor-only layout

Find the `layoutContent` function (or similar) and update it:

```swift
// Before (example of what to look for):
EditorPanelView(
    siteViewModel: siteViewModel,
    editorViewModel: editorViewModel,
    contentFile: contentFile
)

// After:
FileViewerRouter(
    node: selectedNode,
    siteViewModel: siteViewModel,
    editorViewModel: editorViewModel
)
```

For hiding preview on non-markdown files, find where the layout mode is checked and add:

```swift
// Determine if we should show preview
var effectiveLayoutMode: EditorLayoutMode {
    guard let node = siteViewModel.selectedNode else {
        return siteViewModel.layoutMode
    }
    // Only markdown files get preview
    if node.fileType != .markdown {
        return .editor  // Force editor-only mode
    }
    return siteViewModel.layoutMode
}
```

Then use `effectiveLayoutMode` instead of `siteViewModel.layoutMode` in the layout switch.

---

### Step 2.6: Update SiteViewModel for Non-Markdown File Selection

**Modify file:** `Victor/ViewModels/SiteViewModel.swift`

The current `selectNode` method loads content only for markdown files. Update it to handle other file types:

Find the `selectNode` function and ensure it works with non-markdown files. The key change is that we should allow selecting any file, not just markdown files:

```swift
// In selectNode(_:) function, find where it checks for markdown:
// The check might look like: guard node.isMarkdownFile else { return }

// Change to allow all files:
guard !node.isDirectory else { return }

// For markdown files in content/, load the ContentFile
// For other files, just select the node without loading special content
```

---

### Step 2.7: Regenerate Xcode Project and Build

After creating all new files:

```bash
cd /Users/karan/Developer/macos/victor
xcodegen generate
xcodebuild -project Victor.xcodeproj -scheme Victor -configuration Debug build
```

---

### Step 2.8: Testing Checklist for Phase 2

- [ ] Can click on image files in sidebar → ImageViewerPanel shows
- [ ] Can zoom in/out on images
- [ ] Can click on YAML/TOML/JSON files → TextViewerPanel shows
- [ ] Can click on CSS/JS files → TextViewerPanel shows
- [ ] Can click on unknown file types → UnsupportedFilePanel shows
- [ ] Preview panel is hidden for non-markdown files
- [ ] Markdown files still work with editor + preview
- [ ] "Open in Default App" buttons work
- [ ] "Reveal in Finder" buttons work

---

## Phase 3: Text File Editing (Write Support) ✅ COMPLETE

### Goal
Enable editing of all text-based files (YAML, TOML, JSON, HTML, CSS, JS) with auto-save.

### Prerequisites
- Phase 2 must be complete
- Understand how `EditorViewModel` handles auto-save

---

### Step 3.1: Create TextFile Model

**Create new file:** `Victor/Models/TextFile.swift`

```swift
import Foundation

/// Represents a plain text file (non-markdown)
@Observable
class TextFile: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let fileType: FileType
    var content: String
    var originalContent: String  // For change detection
    var lastModified: Date

    /// Whether there are unsaved changes
    var hasUnsavedChanges: Bool {
        content != originalContent
    }

    init(url: URL, content: String, lastModified: Date) {
        self.id = UUID()
        self.url = url
        self.fileType = FileType(url: url)
        self.content = content
        self.originalContent = content
        self.lastModified = lastModified
    }

    /// Mark the file as saved (updates original content)
    func markAsSaved() {
        originalContent = content
    }

    // MARK: - Hashable & Equatable

    static func == (lhs: TextFile, rhs: TextFile) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
```

---

### Step 3.2: Create TextEditorViewModel

**Create new file:** `Victor/ViewModels/TextEditorViewModel.swift`

```swift
import Foundation
import SwiftUI

/// ViewModel for editing plain text files (YAML, TOML, JSON, HTML, CSS, JS, etc.)
@MainActor
@Observable
class TextEditorViewModel {
    // MARK: - Properties

    /// The text file being edited (nil if none selected)
    var textFile: TextFile?

    /// Editable content bound to the editor
    var editableContent: String = ""

    /// Whether file has unsaved changes
    var hasUnsavedChanges: Bool {
        guard let file = textFile else { return false }
        return editableContent != file.originalContent
    }

    /// Whether currently saving
    var isSaving: Bool = false

    /// Error message to display
    var errorMessage: String?

    /// Whether auto-save is enabled
    @AppStorage("isAutoSaveEnabled") var isAutoSaveEnabled: Bool = true

    /// Auto-save delay in seconds
    @AppStorage("autoSaveDelay") var autoSaveDelay: Double = 2.0

    // MARK: - Private Properties

    private var autoSaveTask: Task<Void, Never>?

    // MARK: - Public Methods

    /// Load a text file for editing
    func loadFile(_ file: TextFile) {
        // Cancel any pending auto-save
        autoSaveTask?.cancel()

        self.textFile = file
        self.editableContent = file.content
        self.errorMessage = nil
    }

    /// Called when content changes in the editor
    func contentDidChange() {
        guard let file = textFile else { return }
        file.content = editableContent

        // Schedule auto-save if enabled
        if isAutoSaveEnabled && hasUnsavedChanges {
            scheduleAutoSave()
        }
    }

    /// Save the file manually
    func save() async {
        guard let file = textFile else { return }
        guard hasUnsavedChanges else { return }

        isSaving = true
        errorMessage = nil

        do {
            try await FileSystemService.shared.writeFile(to: file.url, content: editableContent)
            file.content = editableContent
            file.markAsSaved()
            file.lastModified = Date()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }

    /// Reload content from disk (discard changes)
    func reloadFromDisk() async {
        guard let file = textFile else { return }

        do {
            let content = try await Task.detached {
                try String(contentsOf: file.url, encoding: .utf8)
            }.value

            file.content = content
            file.originalContent = content
            self.editableContent = content
            self.errorMessage = nil
        } catch {
            errorMessage = "Failed to reload: \(error.localizedDescription)"
        }
    }

    // MARK: - Private Methods

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()

        autoSaveTask = Task {
            // Wait for the debounce interval
            try? await Task.sleep(for: .seconds(autoSaveDelay))

            // Check if task was cancelled
            guard !Task.isCancelled else { return }

            // Perform save
            await save()
        }
    }
}
```

---

### Step 3.3: Create TextEditorPanel View

**Create new file:** `Victor/Views/Editor/TextEditorPanel.swift`

```swift
import SwiftUI
import AppKit

/// Panel for editing plain text files
struct TextEditorPanel: View {
    let textFile: TextFile
    @Bindable var viewModel: TextEditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            textEditorToolbar

            Divider()

            // Editor
            TextEditorTextView(
                text: $viewModel.editableContent,
                fileType: textFile.fileType,
                onTextChange: {
                    viewModel.contentDidChange()
                }
            )
        }
    }

    private var textEditorToolbar: some View {
        HStack {
            // File type icon and name
            Image(systemName: textFile.fileType.systemImage)
                .foregroundStyle(textFile.fileType.defaultColor)

            Text(textFile.url.lastPathComponent)
                .font(.headline)

            // File type badge
            Text(textFile.fileType.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.2))
                .cornerRadius(4)

            // Unsaved indicator
            if viewModel.hasUnsavedChanges {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                    .help("Unsaved changes")
            }

            Spacer()

            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Saving indicator
            if viewModel.isSaving {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Saving...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 20)

            // Save button
            Button {
                Task {
                    await viewModel.save()
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!viewModel.hasUnsavedChanges || viewModel.isSaving)
            .help("Save (⌘S)")

            // Reload button
            Button {
                Task {
                    await viewModel.reloadFromDisk()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload from disk")

            Divider()
                .frame(height: 20)

            // Open in external editor
            Button {
                NSWorkspace.shared.open(textFile.url)
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .help("Open in default app")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// NSTextView wrapper for text editing
struct TextEditorTextView: NSViewRepresentable {
    @Binding var text: String
    let fileType: FileType
    let onTextChange: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        // Configure scroll view
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        // Configure text view
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.autoresizingMask = [.width]
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        // Disable smart quotes and dashes for code editing
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        // Set up delegate
        textView.delegate = context.coordinator

        // Set initial text
        textView.string = text

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update if text differs (avoid cursor jumping)
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextEditorTextView

        init(_ parent: TextEditorTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onTextChange()
        }
    }
}
```

---

### Step 3.4: Add TextFile to FileNode

**Modify file:** `Victor/Models/FileNode.swift`

Add a property to cache TextFile similar to ContentFile:

```swift
// Add after the contentFile property (around line 30):

/// Associated text file (for non-markdown text files)
var textFile: TextFile?
```

---

### Step 3.5: Add TextFile Loading to FileSystemService

**Modify file:** `Victor/Services/FileSystemService.swift`

Add a method to read text files:

```swift
// Add after the readContentFile method:

/// Read a text file from disk
func readTextFile(at url: URL) async throws -> TextFile {
    try await Task.detached {
        let content = try String(contentsOf: url, encoding: .utf8)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let modificationDate = attributes[.modificationDate] as? Date ?? Date()

        return TextFile(
            url: url,
            content: content,
            lastModified: modificationDate
        )
    }.value
}
```

---

### Step 3.6: Update SiteViewModel for TextFile Loading

**Modify file:** `Victor/ViewModels/SiteViewModel.swift`

Add properties and methods for text file handling:

```swift
// Add property near other ViewModels:
var textEditorViewModel = TextEditorViewModel()

// In the selectNode method, add handling for text files:
// After loading markdown files, add:

// For text files, load the TextFile
if node.fileType.isTextBased && node.fileType != .markdown {
    if node.textFile == nil {
        do {
            let textFile = try await FileSystemService.shared.readTextFile(at: node.url)
            node.textFile = textFile
        } catch {
            print("Failed to load text file: \(error)")
        }
    }

    if let textFile = node.textFile {
        textEditorViewModel.loadFile(textFile)
    }
}
```

---

### Step 3.7: Update FileViewerRouter for Text Editing

**Modify file:** `Victor/Views/Viewers/FileViewerRouter.swift`

Update to use `TextEditorPanel` instead of `TextViewerPanel`:

```swift
// Replace the TextViewerPanel case with:

case .yaml, .toml, .json, .html, .css, .javascript, .typescript,
     .scss, .sass, .less, .xml, .go, .plainText:
    if let textFile = node.textFile {
        TextEditorPanel(
            textFile: textFile,
            viewModel: siteViewModel.textEditorViewModel
        )
    } else {
        // Fallback to read-only viewer if not loaded yet
        TextViewerPanel(url: node.url, fileType: node.fileType)
    }
```

---

### Step 3.8: Testing Checklist for Phase 3

- [ ] Can edit YAML files and changes appear
- [ ] Can edit TOML files and changes appear
- [ ] Can edit JSON files and changes appear
- [ ] Can edit CSS/JS files and changes appear
- [ ] Unsaved changes indicator (orange dot) appears
- [ ] ⌘S saves the file
- [ ] Auto-save triggers after 2 seconds of no typing
- [ ] Can reload file from disk
- [ ] Undo/redo works (⌘Z/⌘⇧Z)
- [ ] No smart quotes or auto-correct in editor

---

## Phase 4: Hugo Config GUI Editor ✅ COMPLETE

### Goal
Create a form-based editor for Hugo configuration files (hugo.toml, hugo.yaml, hugo.json).

### Prerequisites
- Phase 3 must be complete
- Understand the existing FrontmatterEditorView pattern

---

### Step 4.1: Create HugoConfig Model

**Create new file:** `Victor/Models/HugoConfig.swift`

```swift
import Foundation

/// Represents a Hugo site configuration
@Observable
class HugoConfig {
    // MARK: - Required Fields

    /// The base URL of the site (e.g., "https://example.com/")
    var baseURL: String = ""

    /// The site title
    var title: String = ""

    /// Language code (e.g., "en-us")
    var languageCode: String = "en-us"

    // MARK: - Common Fields

    /// Theme name or array of themes
    var theme: String?

    /// Copyright notice
    var copyright: String?

    /// Whether to include draft content in builds
    var buildDrafts: Bool = false

    /// Whether to include future-dated content
    var buildFuture: Bool = false

    /// Whether to include expired content
    var buildExpired: Bool = false

    /// Whether to generate robots.txt
    var enableRobotsTXT: Bool = false

    /// Summary length for auto-generated summaries
    var summaryLength: Int = 70

    /// Default content language
    var defaultContentLanguage: String = "en"

    /// Time zone for dates
    var timeZone: String?

    // MARK: - Taxonomies

    /// Custom taxonomies (singular: plural)
    var taxonomies: [String: String] = [
        "category": "categories",
        "tag": "tags"
    ]

    // MARK: - Menus

    /// Menu definitions
    var menus: [String: [HugoMenuItem]] = [:]

    // MARK: - Custom Parameters

    /// Site-specific custom parameters (params section)
    var params: [String: Any] = [:]

    // MARK: - Unknown Fields

    /// Fields not recognized by Victor (preserved for round-trip)
    var customFields: [String: Any] = [:]

    // MARK: - Metadata

    /// The source file URL
    var sourceURL: URL?

    /// The original format of the config file
    var sourceFormat: ConfigFormat = .toml

    /// Whether there are unsaved changes
    var hasUnsavedChanges: Bool = false

    // MARK: - Initialization

    init() {}

    init(from dictionary: [String: Any], format: ConfigFormat, url: URL) {
        self.sourceURL = url
        self.sourceFormat = format

        // Parse known fields
        if let baseURL = dictionary["baseURL"] as? String {
            self.baseURL = baseURL
        }
        if let title = dictionary["title"] as? String {
            self.title = title
        }
        if let languageCode = dictionary["languageCode"] as? String {
            self.languageCode = languageCode
        }
        if let theme = dictionary["theme"] as? String {
            self.theme = theme
        }
        if let copyright = dictionary["copyright"] as? String {
            self.copyright = copyright
        }
        if let buildDrafts = dictionary["buildDrafts"] as? Bool {
            self.buildDrafts = buildDrafts
        }
        if let buildFuture = dictionary["buildFuture"] as? Bool {
            self.buildFuture = buildFuture
        }
        if let buildExpired = dictionary["buildExpired"] as? Bool {
            self.buildExpired = buildExpired
        }
        if let enableRobotsTXT = dictionary["enableRobotsTXT"] as? Bool {
            self.enableRobotsTXT = enableRobotsTXT
        }
        if let summaryLength = dictionary["summaryLength"] as? Int {
            self.summaryLength = summaryLength
        }
        if let timeZone = dictionary["timeZone"] as? String {
            self.timeZone = timeZone
        }
        if let taxonomies = dictionary["taxonomies"] as? [String: String] {
            self.taxonomies = taxonomies
        }
        if let params = dictionary["params"] as? [String: Any] {
            self.params = params
        }

        // Store all other fields as custom
        let knownFields: Set<String> = [
            "baseURL", "title", "languageCode", "theme", "copyright",
            "buildDrafts", "buildFuture", "buildExpired", "enableRobotsTXT",
            "summaryLength", "timeZone", "taxonomies", "params", "menus"
        ]

        for (key, value) in dictionary where !knownFields.contains(key) {
            customFields[key] = value
        }
    }
}

/// Represents a menu item in Hugo config
struct HugoMenuItem: Identifiable, Codable {
    let id: UUID
    var name: String
    var url: String?
    var pageRef: String?
    var weight: Int
    var identifier: String?
    var parent: String?

    init(name: String, url: String? = nil, pageRef: String? = nil, weight: Int = 0) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.pageRef = pageRef
        self.weight = weight
    }
}
```

---

### Step 4.2: Create HugoConfigParser Service

**Create new file:** `Victor/Services/HugoConfigParser.swift`

```swift
import Foundation
import Yams
import TOMLKit

/// Service for parsing and serializing Hugo configuration files
class HugoConfigParser {
    static let shared = HugoConfigParser()

    private init() {}

    // MARK: - Detection

    /// Find the Hugo config file in a site directory
    func findConfigFile(in siteURL: URL) -> URL? {
        let fileManager = FileManager.default

        // Check for single-file configs in order of precedence
        let configNames = [
            "hugo.toml", "hugo.yaml", "hugo.json",
            "config.toml", "config.yaml", "config.json"
        ]

        for name in configNames {
            let url = siteURL.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    // MARK: - Parsing

    /// Parse a Hugo config file
    func parseConfig(at url: URL) async throws -> HugoConfig {
        let content = try await Task.detached {
            try String(contentsOf: url, encoding: .utf8)
        }.value

        let format = ConfigFormat(filename: url.lastPathComponent) ?? .toml
        let dictionary = try parse(content: content, format: format)

        return HugoConfig(from: dictionary, format: format, url: url)
    }

    /// Parse content based on format
    private func parse(content: String, format: ConfigFormat) throws -> [String: Any] {
        switch format {
        case .toml:
            return try parseTOML(content)
        case .yaml:
            return try parseYAML(content)
        case .json:
            return try parseJSON(content)
        }
    }

    private func parseTOML(_ content: String) throws -> [String: Any] {
        let table = try TOMLTable(string: content)
        return convertTOMLToDict(table)
    }

    private func parseYAML(_ content: String) throws -> [String: Any] {
        guard let result = try Yams.load(yaml: content) as? [String: Any] else {
            throw ConfigError.invalidFormat
        }
        return result
    }

    private func parseJSON(_ content: String) throws -> [String: Any] {
        guard let data = content.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError.invalidFormat
        }
        return result
    }

    // MARK: - Serialization

    /// Serialize a HugoConfig back to string
    func serialize(_ config: HugoConfig) throws -> String {
        var dictionary: [String: Any] = [:]

        // Required fields
        dictionary["baseURL"] = config.baseURL
        dictionary["title"] = config.title
        dictionary["languageCode"] = config.languageCode

        // Optional fields
        if let theme = config.theme, !theme.isEmpty {
            dictionary["theme"] = theme
        }
        if let copyright = config.copyright, !copyright.isEmpty {
            dictionary["copyright"] = copyright
        }
        if config.buildDrafts {
            dictionary["buildDrafts"] = true
        }
        if config.buildFuture {
            dictionary["buildFuture"] = true
        }
        if config.buildExpired {
            dictionary["buildExpired"] = true
        }
        if config.enableRobotsTXT {
            dictionary["enableRobotsTXT"] = true
        }
        if config.summaryLength != 70 {
            dictionary["summaryLength"] = config.summaryLength
        }
        if let timeZone = config.timeZone, !timeZone.isEmpty {
            dictionary["timeZone"] = timeZone
        }

        // Taxonomies (if different from default)
        let defaultTaxonomies = ["category": "categories", "tag": "tags"]
        if config.taxonomies != defaultTaxonomies {
            dictionary["taxonomies"] = config.taxonomies
        }

        // Params
        if !config.params.isEmpty {
            dictionary["params"] = config.params
        }

        // Custom fields
        for (key, value) in config.customFields {
            dictionary[key] = value
        }

        return try serialize(dictionary: dictionary, format: config.sourceFormat)
    }

    private func serialize(dictionary: [String: Any], format: ConfigFormat) throws -> String {
        switch format {
        case .toml:
            return try serializeToTOML(dictionary)
        case .yaml:
            return try serializeToYAML(dictionary)
        case .json:
            return try serializeToJSON(dictionary)
        }
    }

    private func serializeToTOML(_ dictionary: [String: Any]) throws -> String {
        // Convert dictionary to TOML string
        // This is a simplified implementation - TOMLKit doesn't have direct dict serialization
        var lines: [String] = []

        for (key, value) in dictionary.sorted(by: { $0.key < $1.key }) {
            if let stringValue = value as? String {
                lines.append("\(key) = \"\(stringValue)\"")
            } else if let boolValue = value as? Bool {
                lines.append("\(key) = \(boolValue)")
            } else if let intValue = value as? Int {
                lines.append("\(key) = \(intValue)")
            } else if let dictValue = value as? [String: Any] {
                lines.append("")
                lines.append("[\(key)]")
                for (subKey, subValue) in dictValue.sorted(by: { $0.key < $1.key }) {
                    if let stringValue = subValue as? String {
                        lines.append("\(subKey) = \"\(stringValue)\"")
                    } else if let boolValue = subValue as? Bool {
                        lines.append("\(subKey) = \(boolValue)")
                    } else if let intValue = subValue as? Int {
                        lines.append("\(subKey) = \(intValue)")
                    }
                }
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func serializeToYAML(_ dictionary: [String: Any]) throws -> String {
        return try Yams.dump(object: dictionary)
    }

    private func serializeToJSON(_ dictionary: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: dictionary,
            options: [.prettyPrinted, .sortedKeys]
        )
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Helpers

    private func convertTOMLToDict(_ table: TOMLTable) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in table {
            result[key] = convertTOMLValue(value)
        }
        return result
    }

    private func convertTOMLValue(_ value: TOMLValue) -> Any {
        switch value {
        case .string(let s):
            return s
        case .int(let i):
            return i
        case .bool(let b):
            return b
        case .double(let d):
            return d
        case .table(let t):
            return convertTOMLToDict(t)
        case .array(let a):
            return a.map { convertTOMLValue($0) }
        default:
            return String(describing: value)
        }
    }
}

enum ConfigError: LocalizedError {
    case invalidFormat
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid configuration file format"
        case .fileNotFound:
            return "Configuration file not found"
        }
    }
}
```

---

### Step 4.3: Create ConfigEditorView

**Create new directory:** `Victor/Views/ConfigEditor/`

**Create new file:** `Victor/Views/ConfigEditor/ConfigEditorView.swift`

```swift
import SwiftUI

/// Main view for editing Hugo configuration
struct ConfigEditorView: View {
    @Bindable var config: HugoConfig
    let onSave: () async -> Void

    @State private var selectedTab: ConfigTab = .essentials
    @State private var showRawEditor = false
    @State private var isSaving = false

    enum ConfigTab: String, CaseIterable {
        case essentials = "Essentials"
        case content = "Content"
        case taxonomies = "Taxonomies"
        case advanced = "Advanced"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            configToolbar

            Divider()

            if showRawEditor {
                // Raw editor mode
                ConfigRawEditorView(config: config)
            } else {
                // Form editor mode
                TabView(selection: $selectedTab) {
                    ConfigEssentialsTab(config: config)
                        .tabItem { Text("Essentials") }
                        .tag(ConfigTab.essentials)

                    ConfigContentTab(config: config)
                        .tabItem { Text("Content") }
                        .tag(ConfigTab.content)

                    ConfigTaxonomiesTab(config: config)
                        .tabItem { Text("Taxonomies") }
                        .tag(ConfigTab.taxonomies)

                    ConfigAdvancedTab(config: config)
                        .tabItem { Text("Advanced") }
                        .tag(ConfigTab.advanced)
                }
                .padding()
            }
        }
    }

    private var configToolbar: some View {
        HStack {
            // Config file icon
            Image(systemName: "gearshape.fill")
                .foregroundStyle(.orange)

            // File name
            if let url = config.sourceURL {
                Text(url.lastPathComponent)
                    .font(.headline)
            } else {
                Text("Hugo Configuration")
                    .font(.headline)
            }

            // Format badge
            Text(config.sourceFormat.rawValue.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.2))
                .cornerRadius(4)

            // Unsaved indicator
            if config.hasUnsavedChanges {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                    .help("Unsaved changes")
            }

            Spacer()

            // Toggle between form and raw
            Picker("View", selection: $showRawEditor) {
                Text("Form").tag(false)
                Text("Raw").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)

            Divider()
                .frame(height: 20)

            // Save button
            Button {
                Task {
                    isSaving = true
                    await onSave()
                    isSaving = false
                }
            } label: {
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .disabled(!config.hasUnsavedChanges || isSaving)
            .keyboardShortcut("s", modifiers: .command)
            .help("Save (⌘S)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Essentials Tab

struct ConfigEssentialsTab: View {
    @Bindable var config: HugoConfig

    var body: some View {
        Form {
            Section("Site Identity") {
                TextField("Base URL:", text: $config.baseURL)
                    .textFieldStyle(.roundedBorder)
                    .help("The absolute URL of your site (e.g., https://example.com/)")
                    .onChange(of: config.baseURL) { _, _ in
                        config.hasUnsavedChanges = true
                    }

                TextField("Title:", text: $config.title)
                    .textFieldStyle(.roundedBorder)
                    .help("The title of your site")
                    .onChange(of: config.title) { _, _ in
                        config.hasUnsavedChanges = true
                    }

                TextField("Language Code:", text: $config.languageCode)
                    .textFieldStyle(.roundedBorder)
                    .help("RFC 5646 language code (e.g., en-us)")
                    .onChange(of: config.languageCode) { _, _ in
                        config.hasUnsavedChanges = true
                    }
            }

            Section("Theme") {
                TextField("Theme:", text: Binding(
                    get: { config.theme ?? "" },
                    set: { config.theme = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .help("Theme name or comma-separated list")
                .onChange(of: config.theme) { _, _ in
                    config.hasUnsavedChanges = true
                }
            }

            Section("Copyright") {
                TextField("Copyright:", text: Binding(
                    get: { config.copyright ?? "" },
                    set: { config.copyright = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .help("Copyright notice for your site")
                .onChange(of: config.copyright) { _, _ in
                    config.hasUnsavedChanges = true
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Content Tab

struct ConfigContentTab: View {
    @Bindable var config: HugoConfig

    var body: some View {
        Form {
            Section("Build Options") {
                Toggle("Build Drafts", isOn: $config.buildDrafts)
                    .help("Include draft content in builds")
                    .onChange(of: config.buildDrafts) { _, _ in
                        config.hasUnsavedChanges = true
                    }

                Toggle("Build Future", isOn: $config.buildFuture)
                    .help("Include future-dated content")
                    .onChange(of: config.buildFuture) { _, _ in
                        config.hasUnsavedChanges = true
                    }

                Toggle("Build Expired", isOn: $config.buildExpired)
                    .help("Include expired content")
                    .onChange(of: config.buildExpired) { _, _ in
                        config.hasUnsavedChanges = true
                    }
            }

            Section("Output") {
                Toggle("Enable robots.txt", isOn: $config.enableRobotsTXT)
                    .help("Generate robots.txt file")
                    .onChange(of: config.enableRobotsTXT) { _, _ in
                        config.hasUnsavedChanges = true
                    }

                Stepper("Summary Length: \(config.summaryLength) words",
                        value: $config.summaryLength, in: 10...500, step: 10)
                    .help("Default length for auto-generated summaries")
                    .onChange(of: config.summaryLength) { _, _ in
                        config.hasUnsavedChanges = true
                    }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Taxonomies Tab

struct ConfigTaxonomiesTab: View {
    @Bindable var config: HugoConfig
    @State private var newSingular = ""
    @State private var newPlural = ""

    var body: some View {
        Form {
            Section("Taxonomies") {
                ForEach(Array(config.taxonomies.keys.sorted()), id: \.self) { singular in
                    HStack {
                        Text(singular)
                            .frame(width: 100, alignment: .trailing)
                        Text("→")
                            .foregroundStyle(.secondary)
                        Text(config.taxonomies[singular] ?? "")
                        Spacer()
                        Button(role: .destructive) {
                            config.taxonomies.removeValue(forKey: singular)
                            config.hasUnsavedChanges = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("singular", text: $newSingular)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Text("→")
                        .foregroundStyle(.secondary)
                    TextField("plural", text: $newPlural)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Button("Add") {
                        if !newSingular.isEmpty && !newPlural.isEmpty {
                            config.taxonomies[newSingular] = newPlural
                            config.hasUnsavedChanges = true
                            newSingular = ""
                            newPlural = ""
                        }
                    }
                    .disabled(newSingular.isEmpty || newPlural.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced Tab

struct ConfigAdvancedTab: View {
    @Bindable var config: HugoConfig

    var body: some View {
        Form {
            Section("Localization") {
                TextField("Default Language:", text: $config.defaultContentLanguage)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: config.defaultContentLanguage) { _, _ in
                        config.hasUnsavedChanges = true
                    }

                TextField("Time Zone:", text: Binding(
                    get: { config.timeZone ?? "" },
                    set: { config.timeZone = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .help("IANA time zone (e.g., America/New_York)")
                .onChange(of: config.timeZone) { _, _ in
                    config.hasUnsavedChanges = true
                }
            }

            if !config.customFields.isEmpty {
                Section("Other Fields (Preserved)") {
                    ForEach(Array(config.customFields.keys.sorted()), id: \.self) { key in
                        HStack {
                            Text(key)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(describing: config.customFields[key] ?? ""))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Raw Editor

struct ConfigRawEditorView: View {
    @Bindable var config: HugoConfig
    @State private var rawContent: String = ""

    var body: some View {
        TextEditor(text: $rawContent)
            .font(.system(.body, design: .monospaced))
            .padding()
            .onAppear {
                loadRawContent()
            }
    }

    private func loadRawContent() {
        do {
            rawContent = try HugoConfigParser.shared.serialize(config)
        } catch {
            rawContent = "// Error serializing config: \(error.localizedDescription)"
        }
    }
}
```

---

### Step 4.4: Update FileViewerRouter for Config Files

**Modify file:** `Victor/Views/Viewers/FileViewerRouter.swift`

Add handling for config files before the regular YAML/TOML/JSON handling:

```swift
// At the start of the body, add:

// Check if this is a Hugo config file
if node.isConfigFile {
    if let config = siteViewModel.hugoConfig {
        ConfigEditorView(config: config) {
            await siteViewModel.saveHugoConfig()
        }
    } else {
        // Config not loaded yet - show loading
        ProgressView("Loading configuration...")
            .task {
                await siteViewModel.loadHugoConfig(from: node.url)
            }
    }
} else {
    // ... rest of the existing switch statement
}
```

---

### Step 4.5: Add Config Loading to SiteViewModel

**Modify file:** `Victor/ViewModels/SiteViewModel.swift`

Add properties and methods for Hugo config:

```swift
// Add property:
var hugoConfig: HugoConfig?

// Add methods:
func loadHugoConfig(from url: URL) async {
    do {
        hugoConfig = try await HugoConfigParser.shared.parseConfig(at: url)
    } catch {
        print("Failed to load Hugo config: \(error)")
    }
}

func saveHugoConfig() async {
    guard let config = hugoConfig, let url = config.sourceURL else { return }

    do {
        let content = try HugoConfigParser.shared.serialize(config)
        try await FileSystemService.shared.writeFile(to: url, content: content)
        config.hasUnsavedChanges = false
    } catch {
        print("Failed to save Hugo config: \(error)")
    }
}
```

---

### Step 4.6: Testing Checklist for Phase 4

- [ ] Clicking hugo.toml opens the config editor
- [ ] Can edit baseURL, title, languageCode
- [ ] Can toggle buildDrafts, buildFuture, buildExpired
- [ ] Can add/remove taxonomies
- [ ] Unsaved indicator appears when changes made
- [ ] ⌘S saves the config
- [ ] Can switch between Form and Raw views
- [ ] Unknown fields are preserved after save

---

## Phase 5: Data & Archetypes Management ⏳ NEXT UP

### Goal
Enable structured editing of Hugo data files, content archetypes, and i18n translation files with purpose-built editors.

### Prerequisites
- Phase 3 must be complete (text editing infrastructure)
- Understand how `FrontmatterEditorView` handles dynamic form generation

---

### Understanding Hugo's Special Directories

#### `data/` - Structured Data Files
Hugo data files provide structured data accessible in templates via `.Site.Data`:
- Navigation menus, team lists, product catalogs
- Formats: YAML, JSON, TOML
- Nested structures common (arrays of objects)
- Accessed as `.Site.Data.filename.key`

#### `archetypes/` - Content Templates
Templates used when creating content with `hugo new`:
- Define default frontmatter for new content types
- Can include body content templates
- Support Go template syntax (e.g., `{{ .Date }}`)
- Named by content type: `posts.md`, `projects.md`, `default.md`

#### `i18n/` - Translation Strings
Internationalization files for multi-language sites:
- One file per language: `en.yaml`, `fr.yaml`, `de.toml`
- Key-value pairs for translation strings
- Support pluralization with `one`, `other` keys

---

### Step 5.1: Create DataFile Model

**Create new file:** `Victor/Models/DataFile.swift`

```swift
import Foundation

/// Represents a Hugo data file (YAML/JSON/TOML in data/)
@Observable
class DataFile: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let format: ConfigFormat  // Reuse from Phase 4
    var data: Any  // Can be [String: Any] or [[String: Any]]
    var originalData: Any
    var lastModified: Date

    /// Whether this is an array at the root (common for lists)
    var isArrayRoot: Bool {
        data is [[String: Any]]
    }

    /// Whether there are unsaved changes
    var hasUnsavedChanges: Bool = false

    init(url: URL, data: Any, format: ConfigFormat, lastModified: Date) {
        self.id = UUID()
        self.url = url
        self.format = format
        self.data = data
        self.originalData = data
        self.lastModified = lastModified
    }

    // MARK: - Hashable & Equatable
    static func == (lhs: DataFile, rhs: DataFile) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Represents a single item in a data file (for array-based data)
struct DataItem: Identifiable {
    let id: UUID
    var fields: [String: Any]

    init(fields: [String: Any]) {
        self.id = UUID()
        self.fields = fields
    }
}
```

---

### Step 5.2: Create DataFileParser Service

**Create new file:** `Victor/Services/DataFileParser.swift`

```swift
import Foundation
import Yams
import TOMLKit

/// Service for parsing and serializing Hugo data files
class DataFileParser {
    static let shared = DataFileParser()
    private init() {}

    /// Parse a data file from disk
    func parseDataFile(at url: URL) async throws -> DataFile {
        let content = try await Task.detached {
            try String(contentsOf: url, encoding: .utf8)
        }.value

        let format = ConfigFormat(filename: url.lastPathComponent) ?? .yaml
        let data = try parse(content: content, format: format)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let modDate = attributes[.modificationDate] as? Date ?? Date()

        return DataFile(url: url, data: data, format: format, lastModified: modDate)
    }

    /// Parse content based on format (returns Any - dict or array)
    private func parse(content: String, format: ConfigFormat) throws -> Any {
        switch format {
        case .yaml:
            guard let result = try Yams.load(yaml: content) else {
                throw DataFileError.emptyFile
            }
            return result
        case .json:
            guard let data = content.data(using: .utf8) else {
                throw DataFileError.invalidEncoding
            }
            return try JSONSerialization.jsonObject(with: data)
        case .toml:
            let table = try TOMLTable(string: content)
            return convertTOMLToDict(table)
        }
    }

    /// Serialize data back to string
    func serialize(_ dataFile: DataFile) throws -> String {
        switch dataFile.format {
        case .yaml:
            return try Yams.dump(object: dataFile.data)
        case .json:
            let data = try JSONSerialization.data(
                withJSONObject: dataFile.data,
                options: [.prettyPrinted, .sortedKeys]
            )
            return String(data: data, encoding: .utf8) ?? ""
        case .toml:
            // TOML serialization (simplified)
            guard let dict = dataFile.data as? [String: Any] else {
                throw DataFileError.invalidStructure
            }
            return try serializeToTOML(dict)
        }
    }

    // MARK: - TOML Helpers (reuse from HugoConfigParser)

    private func convertTOMLToDict(_ table: TOMLTable) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in table {
            result[key] = convertTOMLValue(value)
        }
        return result
    }

    private func convertTOMLValue(_ value: TOMLValue) -> Any {
        switch value {
        case .string(let s): return s
        case .int(let i): return i
        case .bool(let b): return b
        case .double(let d): return d
        case .table(let t): return convertTOMLToDict(t)
        case .array(let a): return a.map { convertTOMLValue($0) }
        default: return String(describing: value)
        }
    }

    private func serializeToTOML(_ dict: [String: Any]) throws -> String {
        // Reuse serialization logic from HugoConfigParser
        var lines: [String] = []
        for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
            lines.append(serializeTOMLValue(key: key, value: value))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func serializeTOMLValue(key: String, value: Any) -> String {
        if let s = value as? String { return "\(key) = \"\(s)\"" }
        if let b = value as? Bool { return "\(key) = \(b)" }
        if let i = value as? Int { return "\(key) = \(i)" }
        if let d = value as? Double { return "\(key) = \(d)" }
        return "# \(key) = <complex value>"
    }
}

enum DataFileError: LocalizedError {
    case emptyFile
    case invalidEncoding
    case invalidStructure

    var errorDescription: String? {
        switch self {
        case .emptyFile: return "The data file is empty"
        case .invalidEncoding: return "Could not read file encoding"
        case .invalidStructure: return "Invalid data structure for format"
        }
    }
}
```

---

### Step 5.3: Create DataFileEditorView

**Create new directory:** `Victor/Views/DataEditor/`

**Create new file:** `Victor/Views/DataEditor/DataFileEditorView.swift`

```swift
import SwiftUI

/// Editor for Hugo data files with dynamic form generation
struct DataFileEditorView: View {
    @Bindable var dataFile: DataFile
    let onSave: () async -> Void

    @State private var showRawEditor = false
    @State private var isSaving = false
    @State private var expandedSections: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            dataToolbar
            Divider()

            if showRawEditor {
                DataRawEditorView(dataFile: dataFile)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let dict = dataFile.data as? [String: Any] {
                            DynamicDictEditor(
                                data: Binding(
                                    get: { dict },
                                    set: {
                                        dataFile.data = $0
                                        dataFile.hasUnsavedChanges = true
                                    }
                                ),
                                path: [],
                                expandedSections: $expandedSections
                            )
                        } else if let array = dataFile.data as? [Any] {
                            DynamicArrayEditor(
                                data: Binding(
                                    get: { array },
                                    set: {
                                        dataFile.data = $0
                                        dataFile.hasUnsavedChanges = true
                                    }
                                ),
                                path: []
                            )
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private var dataToolbar: some View {
        HStack {
            Image(systemName: "tablecells")
                .foregroundStyle(.blue)

            Text(dataFile.url.lastPathComponent)
                .font(.headline)

            Text(dataFile.format.rawValue.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.2))
                .cornerRadius(4)

            if dataFile.hasUnsavedChanges {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
            }

            Spacer()

            Picker("View", selection: $showRawEditor) {
                Text("Form").tag(false)
                Text("Raw").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)

            Divider().frame(height: 20)

            Button {
                Task {
                    isSaving = true
                    await onSave()
                    isSaving = false
                }
            } label: {
                if isSaving {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .disabled(!dataFile.hasUnsavedChanges || isSaving)
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Dynamically generated editor for dictionary data
struct DynamicDictEditor: View {
    @Binding var data: [String: Any]
    let path: [String]
    @Binding var expandedSections: Set<String>

    var body: some View {
        ForEach(Array(data.keys.sorted()), id: \.self) { key in
            DynamicFieldEditor(
                key: key,
                value: Binding(
                    get: { data[key] ?? "" },
                    set: { data[key] = $0 }
                ),
                path: path + [key],
                expandedSections: $expandedSections
            )
        }
    }
}

/// Editor for a single field that adapts to the value type
struct DynamicFieldEditor: View {
    let key: String
    @Binding var value: Any
    let path: [String]
    @Binding var expandedSections: Set<String>

    private var pathKey: String { path.joined(separator: ".") }

    var body: some View {
        Group {
            if let stringValue = value as? String {
                LabeledContent(key) {
                    TextField("", text: Binding(
                        get: { stringValue },
                        set: { value = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            } else if let boolValue = value as? Bool {
                Toggle(key, isOn: Binding(
                    get: { boolValue },
                    set: { value = $0 }
                ))
            } else if let intValue = value as? Int {
                LabeledContent(key) {
                    TextField("", value: Binding(
                        get: { intValue },
                        set: { value = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                }
            } else if let dictValue = value as? [String: Any] {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedSections.contains(pathKey) },
                        set: { if $0 { expandedSections.insert(pathKey) } else { expandedSections.remove(pathKey) } }
                    )
                ) {
                    DynamicDictEditor(
                        data: Binding(
                            get: { dictValue },
                            set: { value = $0 }
                        ),
                        path: path,
                        expandedSections: $expandedSections
                    )
                    .padding(.leading, 16)
                } label: {
                    Label(key, systemImage: "folder")
                }
            } else if let arrayValue = value as? [Any] {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedSections.contains(pathKey) },
                        set: { if $0 { expandedSections.insert(pathKey) } else { expandedSections.remove(pathKey) } }
                    )
                ) {
                    DynamicArrayEditor(
                        data: Binding(
                            get: { arrayValue },
                            set: { value = $0 }
                        ),
                        path: path
                    )
                    .padding(.leading, 16)
                } label: {
                    Label("\(key) (\(arrayValue.count) items)", systemImage: "list.bullet")
                }
            } else {
                LabeledContent(key) {
                    Text(String(describing: value))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Editor for array data
struct DynamicArrayEditor: View {
    @Binding var data: [Any]
    let path: [String]

    var body: some View {
        ForEach(Array(data.indices), id: \.self) { index in
            HStack {
                Text("[\(index)]")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 30)

                if let stringItem = data[index] as? String {
                    TextField("", text: Binding(
                        get: { stringItem },
                        set: { data[index] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                } else if let dictItem = data[index] as? [String: Any] {
                    // Show summary of dict item
                    Text(dictItem.keys.prefix(3).joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    data.remove(at: index)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }

        Button {
            // Add new item (empty string for simple arrays)
            data.append("")
        } label: {
            Label("Add Item", systemImage: "plus")
        }
        .buttonStyle(.bordered)
    }
}

/// Raw text editor for data files
struct DataRawEditorView: View {
    @Bindable var dataFile: DataFile
    @State private var rawContent: String = ""

    var body: some View {
        TextEditor(text: $rawContent)
            .font(.system(.body, design: .monospaced))
            .padding()
            .onAppear { loadRawContent() }
            .onChange(of: rawContent) { _, _ in
                dataFile.hasUnsavedChanges = true
            }
    }

    private func loadRawContent() {
        do {
            rawContent = try DataFileParser.shared.serialize(dataFile)
        } catch {
            rawContent = "// Error: \(error.localizedDescription)"
        }
    }
}
```

---

### Step 5.4: Create Archetype Model and Manager

**Create new file:** `Victor/Models/Archetype.swift`

```swift
import Foundation

/// Represents a Hugo archetype (content template)
@Observable
class Archetype: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var content: String
    var originalContent: String

    /// The content type this archetype creates (derived from filename)
    var contentType: String {
        let name = url.deletingPathExtension().lastPathComponent
        return name == "default" ? "default" : name
    }

    /// Whether this is the default archetype
    var isDefault: Bool {
        url.deletingPathExtension().lastPathComponent == "default"
    }

    /// Extract frontmatter preview from the archetype
    var frontmatterPreview: String {
        let lines = content.components(separatedBy: .newlines)
        guard let startIndex = lines.firstIndex(where: { $0.hasPrefix("---") || $0.hasPrefix("+++") }) else {
            return "(no frontmatter)"
        }

        let delimiter = lines[startIndex]
        var endIndex = startIndex + 1
        while endIndex < lines.count && lines[endIndex] != delimiter {
            endIndex += 1
        }

        return lines[startIndex...min(endIndex, lines.count - 1)].joined(separator: "\n")
    }

    var hasUnsavedChanges: Bool {
        content != originalContent
    }

    init(url: URL, content: String) {
        self.id = UUID()
        self.url = url
        self.content = content
        self.originalContent = content
    }

    static func == (lhs: Archetype, rhs: Archetype) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
```

**Create new file:** `Victor/Views/Archetypes/ArchetypeManagerView.swift`

```swift
import SwiftUI

/// Manager view for Hugo archetypes
struct ArchetypeManagerView: View {
    let archetypesURL: URL
    @State private var archetypes: [Archetype] = []
    @State private var selectedArchetype: Archetype?
    @State private var isLoading = true
    @State private var showNewArchetypeSheet = false

    var body: some View {
        HSplitView {
            // Archetype list
            VStack(spacing: 0) {
                archetypeListHeader
                Divider()

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if archetypes.isEmpty {
                    emptyState
                } else {
                    List(archetypes, selection: $selectedArchetype) { archetype in
                        ArchetypeRow(archetype: archetype)
                    }
                }
            }
            .frame(minWidth: 200, maxWidth: 300)

            // Archetype editor
            if let archetype = selectedArchetype {
                ArchetypeEditorView(archetype: archetype) {
                    await saveArchetype(archetype)
                }
            } else {
                Text("Select an archetype to edit")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await loadArchetypes() }
        .sheet(isPresented: $showNewArchetypeSheet) {
            NewArchetypeSheet(archetypesURL: archetypesURL) { newArchetype in
                archetypes.append(newArchetype)
                selectedArchetype = newArchetype
            }
        }
    }

    private var archetypeListHeader: some View {
        HStack {
            Text("Archetypes")
                .font(.headline)
            Spacer()
            Button {
                showNewArchetypeSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .help("Create new archetype")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No archetypes found")
                .foregroundStyle(.secondary)
            Button("Create Default Archetype") {
                showNewArchetypeSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadArchetypes() async {
        isLoading = true
        defer { isLoading = false }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: archetypesURL,
            includingPropertiesForKeys: nil
        ) else { return }

        var loaded: [Archetype] = []
        for url in contents where url.pathExtension == "md" {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                loaded.append(Archetype(url: url, content: content))
            }
        }

        archetypes = loaded.sorted { $0.contentType < $1.contentType }
    }

    private func saveArchetype(_ archetype: Archetype) async {
        do {
            try archetype.content.write(to: archetype.url, atomically: true, encoding: .utf8)
            archetype.originalContent = archetype.content
        } catch {
            print("Failed to save archetype: \(error)")
        }
    }
}

struct ArchetypeRow: View {
    let archetype: Archetype

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(archetype.contentType)
                    .font(.headline)
                if archetype.isDefault {
                    Text("DEFAULT")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2))
                        .cornerRadius(4)
                }
                if archetype.hasUnsavedChanges {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                }
            }
            Text(archetype.url.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct ArchetypeEditorView: View {
    @Bindable var archetype: Archetype
    let onSave: () async -> Void

    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.purple)
                Text(archetype.url.lastPathComponent)
                    .font(.headline)

                if archetype.hasUnsavedChanges {
                    Circle().fill(.orange).frame(width: 8, height: 8)
                }

                Spacer()

                Text("Creates: \(archetype.contentType)/")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider().frame(height: 20)

                Button {
                    Task {
                        isSaving = true
                        await onSave()
                        isSaving = false
                    }
                } label: {
                    if isSaving {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                .disabled(!archetype.hasUnsavedChanges || isSaving)
                .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Editor
            TextEditor(text: $archetype.content)
                .font(.system(.body, design: .monospaced))
        }
    }
}

struct NewArchetypeSheet: View {
    let archetypesURL: URL
    let onCreate: (Archetype) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var contentType = ""

    private let defaultContent = """
---
title: "{{ replace .Name "-" " " | title }}"
date: {{ .Date }}
draft: true
---

"""

    var body: some View {
        VStack(spacing: 20) {
            Text("New Archetype")
                .font(.headline)

            TextField("Content type (e.g., posts, projects)", text: $contentType)
                .textFieldStyle(.roundedBorder)

            Text("This will create \(contentType.isEmpty ? "default" : contentType).md")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Create") {
                    createArchetype()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(contentType.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func createArchetype() {
        let filename = "\(contentType).md"
        let url = archetypesURL.appendingPathComponent(filename)

        do {
            try defaultContent.write(to: url, atomically: true, encoding: .utf8)
            onCreate(Archetype(url: url, content: defaultContent))
        } catch {
            print("Failed to create archetype: \(error)")
        }
    }
}
```

---

### Step 5.5: Create Translation Editor

**Create new file:** `Victor/Views/i18n/TranslationEditorView.swift`

```swift
import SwiftUI

/// Model for a translation file
@Observable
class TranslationFile: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let languageCode: String
    var translations: [String: String]
    var originalTranslations: [String: String]

    var hasUnsavedChanges: Bool {
        translations != originalTranslations
    }

    init(url: URL, translations: [String: String]) {
        self.id = UUID()
        self.url = url
        self.languageCode = url.deletingPathExtension().lastPathComponent
        self.translations = translations
        self.originalTranslations = translations
    }

    static func == (lhs: TranslationFile, rhs: TranslationFile) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Editor view for i18n translation files with side-by-side comparison
struct TranslationEditorView: View {
    let i18nURL: URL
    @State private var translationFiles: [TranslationFile] = []
    @State private var selectedLanguages: Set<String> = []
    @State private var allKeys: [String] = []
    @State private var searchText = ""
    @State private var showOnlyMissing = false

    var filteredKeys: [String] {
        var keys = allKeys
        if !searchText.isEmpty {
            keys = keys.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
        if showOnlyMissing {
            keys = keys.filter { key in
                translationFiles.contains { $0.translations[key] == nil }
            }
        }
        return keys
    }

    var body: some View {
        VStack(spacing: 0) {
            translationToolbar
            Divider()

            if translationFiles.isEmpty {
                emptyState
            } else {
                translationTable
            }
        }
        .task { await loadTranslations() }
    }

    private var translationToolbar: some View {
        HStack {
            Image(systemName: "globe")
                .foregroundStyle(.green)
            Text("Translations")
                .font(.headline)

            Spacer()

            // Language toggles
            ForEach(translationFiles) { file in
                Toggle(file.languageCode.uppercased(), isOn: Binding(
                    get: { selectedLanguages.contains(file.languageCode) },
                    set: { if $0 { selectedLanguages.insert(file.languageCode) }
                          else { selectedLanguages.remove(file.languageCode) } }
                ))
                .toggleStyle(.button)
            }

            Divider().frame(height: 20)

            Toggle("Missing only", isOn: $showOnlyMissing)
                .toggleStyle(.button)

            TextField("Search keys...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)

            Divider().frame(height: 20)

            Button {
                Task { await saveAll() }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .disabled(!translationFiles.contains { $0.hasUnsavedChanges })
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No translation files found")
                .foregroundStyle(.secondary)
            Text("Create files in i18n/ directory")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var translationTable: some View {
        let visibleFiles = translationFiles.filter { selectedLanguages.contains($0.languageCode) }

        return ScrollView {
            LazyVStack(spacing: 0) {
                // Header
                HStack {
                    Text("Key")
                        .font(.headline)
                        .frame(width: 200, alignment: .leading)

                    ForEach(visibleFiles) { file in
                        Text(file.languageCode.uppercased())
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Rows
                ForEach(filteredKeys, id: \.self) { key in
                    HStack {
                        Text(key)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 200, alignment: .leading)

                        ForEach(visibleFiles) { file in
                            TextField("", text: Binding(
                                get: { file.translations[key] ?? "" },
                                set: { file.translations[key] = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .background(file.translations[key] == nil ? Color.red.opacity(0.1) : Color.clear)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)

                    Divider()
                }
            }
        }
    }

    private func loadTranslations() async {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: i18nURL, includingPropertiesForKeys: nil) else {
            return
        }

        var files: [TranslationFile] = []
        var keys: Set<String> = []

        for url in contents {
            let ext = url.pathExtension.lowercased()
            guard ["yaml", "yml", "toml", "json"].contains(ext) else { continue }

            if let translations = try? await loadTranslationFile(at: url) {
                files.append(TranslationFile(url: url, translations: translations))
                keys.formUnion(translations.keys)
            }
        }

        translationFiles = files.sorted { $0.languageCode < $1.languageCode }
        allKeys = Array(keys).sorted()
        selectedLanguages = Set(files.prefix(2).map { $0.languageCode })
    }

    private func loadTranslationFile(at url: URL) async throws -> [String: String] {
        let content = try String(contentsOf: url, encoding: .utf8)
        // Simplified: assumes flat key-value structure
        // In production, handle nested structures for pluralization

        if url.pathExtension == "yaml" || url.pathExtension == "yml" {
            if let dict = try Yams.load(yaml: content) as? [String: Any] {
                return dict.compactMapValues { $0 as? String }
            }
        }
        // Add JSON/TOML handling...
        return [:]
    }

    private func saveAll() async {
        for file in translationFiles where file.hasUnsavedChanges {
            do {
                let content = try Yams.dump(object: file.translations)
                try content.write(to: file.url, atomically: true, encoding: .utf8)
                file.originalTranslations = file.translations
            } catch {
                print("Failed to save \(file.languageCode): \(error)")
            }
        }
    }
}
```

---

### Step 5.6: Update FileViewerRouter for Phase 5 Files

**Modify:** `Victor/Views/Viewers/FileViewerRouter.swift`

Add routing for data files, archetypes, and i18n files based on their Hugo role:

```swift
// Add at the start of the switch, before checking fileType:

// Route based on Hugo role
switch node.hugoRole {
case .data:
    if let dataFile = node.dataFile {
        DataFileEditorView(dataFile: dataFile) {
            await siteViewModel.saveDataFile(dataFile)
        }
    } else {
        ProgressView("Loading data file...")
            .task { await siteViewModel.loadDataFile(for: node) }
    }

case .archetype:
    // Archetypes are markdown but need special handling
    if let archetype = node.archetype {
        ArchetypeEditorView(archetype: archetype) {
            await siteViewModel.saveArchetype(archetype)
        }
    } else {
        ProgressView("Loading archetype...")
            .task { await siteViewModel.loadArchetype(for: node) }
    }

case .i18n:
    if let i18nURL = siteViewModel.currentSite?.url.appendingPathComponent("i18n") {
        TranslationEditorView(i18nURL: i18nURL)
    }

default:
    // Continue with existing file type switch...
}
```

---

### Step 5.7: Testing Checklist for Phase 5

- [ ] Data files in `data/` open with DataFileEditorView
- [ ] Can edit string, boolean, number fields in data files
- [ ] Can expand/collapse nested sections
- [ ] Can add/remove array items
- [ ] Can switch between Form and Raw view
- [ ] Archetypes listed in ArchetypeManagerView
- [ ] Can create new archetypes
- [ ] Can edit archetype content with Go template syntax
- [ ] Translation files show side-by-side
- [ ] Missing translations highlighted in red
- [ ] Can filter to show only missing translations
- [ ] All changes save correctly with ⌘S

---

## Phase 6: Asset Management

### Goal
Create a visual browser for static assets with drag-and-drop support for inserting images into markdown content.

### Prerequisites
- Phase 2 must be complete (image viewing)
- Understand how drag-and-drop works in SwiftUI/AppKit

---

### Understanding Hugo Asset Directories

#### `static/` - Static Files
- Files copied as-is to output
- No processing by Hugo Pipes
- Common: images, PDFs, fonts, legacy CSS/JS
- URL: `/filename.ext`

#### `assets/` - Processed Assets
- Files processed by Hugo Pipes
- Image resizing, SCSS compilation, JS bundling
- Fingerprinting for cache busting
- Accessed via `resources.Get`

---

### Step 6.1: Create Asset Model

**Create new file:** `Victor/Models/Asset.swift`

```swift
import Foundation
import AppKit

/// Represents a static asset file
@Observable
class Asset: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let fileType: FileType
    let relativePath: String  // Path relative to static/ or assets/
    let isInAssets: Bool      // true = assets/, false = static/

    // Lazy-loaded properties
    var thumbnail: NSImage?
    var fileSize: Int64?
    var dimensions: CGSize?   // For images
    var modificationDate: Date?

    /// Generate markdown image syntax
    var markdownSyntax: String {
        let path = isInAssets ? relativePath : "/\(relativePath)"
        return "![\(url.deletingPathExtension().lastPathComponent)](\(path))"
    }

    /// Generate Hugo figure shortcode
    var figureShortcode: String {
        let path = isInAssets ? relativePath : "/\(relativePath)"
        return "{{< figure src=\"\(path)\" alt=\"\" caption=\"\" >}}"
    }

    init(url: URL, relativePath: String, isInAssets: Bool) {
        self.id = UUID()
        self.url = url
        self.fileType = FileType(url: url)
        self.relativePath = relativePath
        self.isInAssets = isInAssets
    }

    static func == (lhs: Asset, rhs: Asset) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Asset loading result
enum AssetLoadResult {
    case loading
    case loaded(Asset)
    case error(String)
}
```

---

### Step 6.2: Create AssetService

**Create new file:** `Victor/Services/AssetService.swift`

```swift
import Foundation
import AppKit

/// Service for managing and loading assets
actor AssetService {
    static let shared = AssetService()

    private var thumbnailCache: [URL: NSImage] = [:]
    private let thumbnailSize = CGSize(width: 120, height: 120)

    /// Scan a directory for assets
    func scanAssets(in directory: URL, isAssetsDir: Bool) async throws -> [Asset] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var assets: [Asset] = []

        for case let url as URL in enumerator {
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues?.isDirectory == false else { continue }

            let relativePath = url.path.replacingOccurrences(
                of: directory.path + "/",
                with: ""
            )

            let asset = Asset(url: url, relativePath: relativePath, isInAssets: isAssetsDir)
            await loadAssetMetadata(asset)
            assets.append(asset)
        }

        return assets
    }

    /// Load metadata for an asset
    func loadAssetMetadata(_ asset: Asset) async {
        let fm = FileManager.default

        if let attributes = try? fm.attributesOfItem(atPath: asset.url.path) {
            asset.fileSize = attributes[.size] as? Int64
            asset.modificationDate = attributes[.modificationDate] as? Date
        }

        // Load image dimensions and thumbnail
        if asset.fileType == .image {
            if let image = NSImage(contentsOf: asset.url) {
                asset.dimensions = image.size
                asset.thumbnail = await generateThumbnail(for: image)
            }
        }
    }

    /// Generate a thumbnail for an image
    private func generateThumbnail(for image: NSImage) async -> NSImage {
        let aspectRatio = image.size.width / image.size.height
        var thumbSize = thumbnailSize

        if aspectRatio > 1 {
            thumbSize.height = thumbSize.width / aspectRatio
        } else {
            thumbSize.width = thumbSize.height * aspectRatio
        }

        let thumbnail = NSImage(size: thumbSize)
        thumbnail.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: thumbSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        thumbnail.unlockFocus()

        return thumbnail
    }

    /// Get cached thumbnail or generate one
    func getThumbnail(for asset: Asset) async -> NSImage? {
        if let cached = thumbnailCache[asset.url] {
            return cached
        }

        guard asset.fileType == .image,
              let image = NSImage(contentsOf: asset.url) else {
            return nil
        }

        let thumbnail = await generateThumbnail(for: image)
        thumbnailCache[asset.url] = thumbnail
        return thumbnail
    }
}
```

---

### Step 6.3: Create AssetBrowserView

**Create new directory:** `Victor/Views/AssetBrowser/`

**Create new file:** `Victor/Views/AssetBrowser/AssetBrowserView.swift`

```swift
import SwiftUI
import UniformTypeIdentifiers

/// Main view for browsing and managing assets
struct AssetBrowserView: View {
    let staticURL: URL?
    let assetsURL: URL?
    let onInsert: ((String) -> Void)?  // Callback when inserting into markdown

    @State private var assets: [Asset] = []
    @State private var isLoading = true
    @State private var selectedAsset: Asset?
    @State private var viewMode: AssetViewMode = .grid
    @State private var filterType: AssetFilterType = .all
    @State private var searchText = ""
    @State private var sortOrder: AssetSortOrder = .name

    enum AssetViewMode: String, CaseIterable {
        case grid = "Grid"
        case list = "List"

        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
    }

    enum AssetFilterType: String, CaseIterable {
        case all = "All"
        case images = "Images"
        case documents = "Documents"
        case other = "Other"
    }

    enum AssetSortOrder: String, CaseIterable {
        case name = "Name"
        case date = "Date"
        case size = "Size"
        case type = "Type"
    }

    var filteredAssets: [Asset] {
        var result = assets

        // Apply search
        if !searchText.isEmpty {
            result = result.filter {
                $0.url.lastPathComponent.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Apply filter
        switch filterType {
        case .all: break
        case .images:
            result = result.filter { $0.fileType == .image }
        case .documents:
            result = result.filter { [.pdf, .plainText].contains($0.fileType) }
        case .other:
            result = result.filter { $0.fileType != .image && $0.fileType != .pdf }
        }

        // Apply sort
        switch sortOrder {
        case .name:
            result.sort { $0.url.lastPathComponent < $1.url.lastPathComponent }
        case .date:
            result.sort { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
        case .size:
            result.sort { ($0.fileSize ?? 0) > ($1.fileSize ?? 0) }
        case .type:
            result.sort { $0.fileType.rawValue < $1.fileType.rawValue }
        }

        return result
    }

    var body: some View {
        HSplitView {
            // Asset browser
            VStack(spacing: 0) {
                assetToolbar
                Divider()

                if isLoading {
                    ProgressView("Loading assets...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if assets.isEmpty {
                    emptyState
                } else {
                    assetContent
                }
            }

            // Asset detail panel
            if let asset = selectedAsset {
                AssetDetailPanel(asset: asset, onInsert: onInsert)
                    .frame(minWidth: 250, maxWidth: 300)
            }
        }
        .task { await loadAssets() }
    }

    private var assetToolbar: some View {
        HStack {
            Image(systemName: "photo.on.rectangle.angled")
                .foregroundStyle(.blue)
            Text("Assets")
                .font(.headline)

            Text("\(filteredAssets.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Filter
            Picker("Filter", selection: $filterType) {
                ForEach(AssetFilterType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

            Divider().frame(height: 20)

            // Sort
            Picker("Sort", selection: $sortOrder) {
                ForEach(AssetSortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .frame(width: 80)

            Divider().frame(height: 20)

            // View mode
            Picker("View", selection: $viewMode) {
                ForEach(AssetViewMode.allCases, id: \.self) { mode in
                    Image(systemName: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 80)

            Divider().frame(height: 20)

            // Search
            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No assets found")
                .font(.headline)
            Text("Add files to static/ or assets/ directory")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var assetContent: some View {
        switch viewMode {
        case .grid:
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 16) {
                    ForEach(filteredAssets) { asset in
                        AssetGridItem(asset: asset, isSelected: asset == selectedAsset)
                            .onTapGesture { selectedAsset = asset }
                            .onDrag {
                                NSItemProvider(object: asset.markdownSyntax as NSString)
                            }
                    }
                }
                .padding()
            }

        case .list:
            List(filteredAssets, selection: $selectedAsset) { asset in
                AssetListRow(asset: asset)
                    .onDrag {
                        NSItemProvider(object: asset.markdownSyntax as NSString)
                    }
            }
        }
    }

    private func loadAssets() async {
        isLoading = true
        defer { isLoading = false }

        var allAssets: [Asset] = []

        if let staticURL = staticURL {
            let staticAssets = try? await AssetService.shared.scanAssets(in: staticURL, isAssetsDir: false)
            allAssets.append(contentsOf: staticAssets ?? [])
        }

        if let assetsURL = assetsURL {
            let pipeAssets = try? await AssetService.shared.scanAssets(in: assetsURL, isAssetsDir: true)
            allAssets.append(contentsOf: pipeAssets ?? [])
        }

        assets = allAssets
    }
}

struct AssetGridItem: View {
    let asset: Asset
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail or icon
            Group {
                if let thumbnail = asset.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: asset.fileType.systemImage)
                        .font(.system(size: 32))
                        .foregroundStyle(asset.fileType.defaultColor)
                }
            }
            .frame(width: 100, height: 80)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            // Filename
            Text(asset.url.lastPathComponent)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
}

struct AssetListRow: View {
    let asset: Asset

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail or icon
            Group {
                if let thumbnail = asset.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: asset.fileType.systemImage)
                        .foregroundStyle(asset.fileType.defaultColor)
                }
            }
            .frame(width: 40, height: 40)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.url.lastPathComponent)
                    .font(.body)

                HStack {
                    if let size = asset.fileSize {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    }
                    if let dims = asset.dimensions {
                        Text("•")
                        Text("\(Int(dims.width))×\(Int(dims.height))")
                    }
                    Text("•")
                    Text(asset.isInAssets ? "assets/" : "static/")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct AssetDetailPanel: View {
    let asset: Asset
    let onInsert: ((String) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Details")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Preview
                    if let thumbnail = asset.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .cornerRadius(8)
                    }

                    // Filename
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Filename")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(asset.url.lastPathComponent)
                            .font(.body)
                            .textSelection(.enabled)
                    }

                    // Path
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Path")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(asset.relativePath)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    // Dimensions
                    if let dims = asset.dimensions {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dimensions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(Int(dims.width)) × \(Int(dims.height)) pixels")
                        }
                    }

                    // Size
                    if let size = asset.fileSize {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Size")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        }
                    }

                    // Location
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(asset.isInAssets ? "assets/ (Hugo Pipes)" : "static/ (copied as-is)")
                    }

                    Divider()

                    // Insert buttons
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Insert into content")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            onInsert?(asset.markdownSyntax)
                        } label: {
                            Label("Markdown Image", systemImage: "photo")
                        }
                        .buttonStyle(.bordered)
                        .disabled(onInsert == nil)

                        Button {
                            onInsert?(asset.figureShortcode)
                        } label: {
                            Label("Figure Shortcode", systemImage: "text.below.photo")
                        }
                        .buttonStyle(.bordered)
                        .disabled(onInsert == nil)

                        Button {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(asset.markdownSyntax, forType: .string)
                        } label: {
                            Label("Copy Path", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)
                    }

                    Divider()

                    // Actions
                    HStack {
                        Button {
                            NSWorkspace.shared.open(asset.url)
                        } label: {
                            Label("Open", systemImage: "arrow.up.forward.square")
                        }

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([asset.url])
                        } label: {
                            Label("Reveal", systemImage: "folder")
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
```

---

### Step 6.4: Add Drag-Drop Support to EditorTextView

**Modify:** `Victor/Views/Editor/EditorTextView.swift`

Add drop destination to accept dragged assets:

```swift
// In the NSTextView configuration, add drop support:

// Add to makeNSView or updateNSView:
textView.registerForDraggedTypes([.string, .fileURL])

// Add to Coordinator:
func textView(_ textView: NSTextView, validateDrop info: NSDraggingInfo, proposedCharacterIndex: Int) -> NSDragOperation {
    return .copy
}

func textView(_ textView: NSTextView, performDragOperation info: NSDraggingInfo) -> Bool {
    guard let items = info.draggingPasteboard.pasteboardItems else { return false }

    for item in items {
        if let string = item.string(forType: .string) {
            // Insert markdown at drop location
            let insertionPoint = textView.selectedRange().location
            textView.insertText(string, replacementRange: NSRange(location: insertionPoint, length: 0))
            return true
        }
    }
    return false
}
```

---

### Step 6.5: Testing Checklist for Phase 6

- [ ] Asset browser shows files from both static/ and assets/
- [ ] Grid view shows thumbnails for images
- [ ] List view shows file details
- [ ] Can filter by type (images, documents, other)
- [ ] Can sort by name, date, size, type
- [ ] Can search assets by filename
- [ ] Detail panel shows file info
- [ ] Can drag asset from browser to markdown editor
- [ ] Dropped asset inserts markdown image syntax
- [ ] "Copy Path" button works
- [ ] "Insert Markdown" and "Insert Figure" buttons work
- [ ] Can open asset in default app
- [ ] Can reveal asset in Finder

---

## Phase 7: Template Editing

### Goal
Enable viewing and editing of Hugo templates with Go template syntax awareness and inheritance visualization.

### Prerequisites
- Phase 3 must be complete (text editing)
- Understanding of Hugo's template lookup order

---

### Understanding Hugo Templates

#### Template Directory Structure
```
layouts/
├── _default/
│   ├── baseof.html      # Base template (defines blocks)
│   ├── list.html        # List page template
│   └── single.html      # Single page template
├── partials/
│   ├── header.html
│   ├── footer.html
│   └── meta.html
├── shortcodes/
│   └── custom.html
├── 404.html
└── index.html           # Homepage
```

#### Template Inheritance
- `baseof.html` defines `{{ block "main" . }}` placeholders
- Other templates use `{{ define "main" }}...{{ end }}`
- Partials included with `{{ partial "name" . }}`

---

### Step 7.1: Create Template Model

**Create new file:** `Victor/Models/HugoTemplate.swift`

```swift
import Foundation

/// Represents a Hugo template file
@Observable
class HugoTemplate: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var content: String
    var originalContent: String

    /// Template category
    enum Category: String, CaseIterable {
        case base = "Base"
        case list = "List"
        case single = "Single"
        case partial = "Partial"
        case shortcode = "Shortcode"
        case taxonomy = "Taxonomy"
        case other = "Other"
    }

    var category: Category {
        let path = url.path
        if path.contains("/partials/") { return .partial }
        if path.contains("/shortcodes/") { return .shortcode }
        if url.lastPathComponent == "baseof.html" { return .base }
        if url.lastPathComponent.contains("list") { return .list }
        if url.lastPathComponent.contains("single") { return .single }
        if url.lastPathComponent.contains("taxonomy") || url.lastPathComponent.contains("terms") { return .taxonomy }
        return .other
    }

    /// Extract defined blocks from template
    var definedBlocks: [String] {
        let pattern = #"\{\{\s*define\s+"([^"]+)""#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(content.startIndex..., in: content)

        return regex?.matches(in: content, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[range])
        } ?? []
    }

    /// Extract partial includes
    var includedPartials: [String] {
        let pattern = #"\{\{\s*partial\s+"([^"]+)""#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(content.startIndex..., in: content)

        return regex?.matches(in: content, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[range])
        } ?? []
    }

    /// Check if template extends baseof
    var extendsBaseof: Bool {
        content.contains("define \"main\"") || content.contains("define \"title\"")
    }

    var hasUnsavedChanges: Bool {
        content != originalContent
    }

    init(url: URL, content: String) {
        self.id = UUID()
        self.url = url
        self.content = content
        self.originalContent = content
    }

    static func == (lhs: HugoTemplate, rhs: HugoTemplate) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
```

---

### Step 7.2: Create TemplateEditorView with Syntax Highlighting

**Create new directory:** `Victor/Views/Templates/`

**Create new file:** `Victor/Views/Templates/TemplateEditorView.swift`

```swift
import SwiftUI
import AppKit

/// Editor for Hugo templates with Go template syntax awareness
struct TemplateEditorView: View {
    @Bindable var template: HugoTemplate
    let onSave: () async -> Void
    let allPartials: [String]  // For autocomplete

    @State private var isSaving = false
    @State private var showInspector = true

    var body: some View {
        HSplitView {
            // Editor
            VStack(spacing: 0) {
                templateToolbar
                Divider()

                GoTemplateTextView(
                    text: $template.content,
                    onTextChange: { }
                )
            }

            // Inspector
            if showInspector {
                TemplateInspector(template: template)
                    .frame(minWidth: 200, maxWidth: 250)
            }
        }
    }

    private var templateToolbar: some View {
        HStack {
            // Template info
            Image(systemName: categoryIcon)
                .foregroundStyle(categoryColor)

            Text(template.url.lastPathComponent)
                .font(.headline)

            Text(template.category.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.2))
                .cornerRadius(4)

            if template.hasUnsavedChanges {
                Circle().fill(.orange).frame(width: 8, height: 8)
            }

            Spacer()

            // Insert menu
            Menu {
                Section("Variables") {
                    Button("Page Title") { insertText("{{ .Title }}") }
                    Button("Page Content") { insertText("{{ .Content }}") }
                    Button("Page Date") { insertText("{{ .Date }}") }
                    Button("Site Title") { insertText("{{ .Site.Title }}") }
                }
                Section("Control Flow") {
                    Button("If") { insertText("{{ if . }}\n\n{{ end }}") }
                    Button("Range") { insertText("{{ range . }}\n\n{{ end }}") }
                    Button("With") { insertText("{{ with . }}\n\n{{ end }}") }
                }
                Section("Includes") {
                    Button("Partial") { insertText("{{ partial \"\" . }}") }
                    Button("Define Block") { insertText("{{ define \"\" }}\n\n{{ end }}") }
                    Button("Block") { insertText("{{ block \"\" . }}\n\n{{ end }}") }
                }
            } label: {
                Label("Insert", systemImage: "plus.circle")
            }

            Divider().frame(height: 20)

            Toggle(isOn: $showInspector) {
                Image(systemName: "sidebar.trailing")
            }
            .toggleStyle(.button)

            Divider().frame(height: 20)

            Button {
                Task {
                    isSaving = true
                    await onSave()
                    isSaving = false
                }
            } label: {
                if isSaving {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .disabled(!template.hasUnsavedChanges || isSaving)
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var categoryIcon: String {
        switch template.category {
        case .base: return "rectangle.stack"
        case .list: return "list.bullet.rectangle"
        case .single: return "doc.richtext"
        case .partial: return "square.on.square"
        case .shortcode: return "chevron.left.forwardslash.chevron.right"
        case .taxonomy: return "tag"
        case .other: return "doc"
        }
    }

    private var categoryColor: Color {
        switch template.category {
        case .base: return .purple
        case .list: return .blue
        case .single: return .green
        case .partial: return .orange
        case .shortcode: return .pink
        case .taxonomy: return .teal
        case .other: return .secondary
        }
    }

    private func insertText(_ text: String) {
        // Insert at cursor position
        template.content += text
    }
}

/// Inspector panel showing template metadata
struct TemplateInspector: View {
    let template: HugoTemplate

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Inspector")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Category
                    inspectorSection("Category") {
                        Label(template.category.rawValue, systemImage: "folder")
                    }

                    // Extends baseof
                    if template.extendsBaseof {
                        inspectorSection("Inheritance") {
                            Label("Extends baseof.html", systemImage: "arrow.up.right")
                        }
                    }

                    // Defined blocks
                    if !template.definedBlocks.isEmpty {
                        inspectorSection("Defined Blocks") {
                            ForEach(template.definedBlocks, id: \.self) { block in
                                Label(block, systemImage: "square.dashed")
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }

                    // Included partials
                    if !template.includedPartials.isEmpty {
                        inspectorSection("Includes") {
                            ForEach(template.includedPartials, id: \.self) { partial in
                                Label(partial, systemImage: "square.on.square")
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }

                    // Hugo docs link
                    inspectorSection("Documentation") {
                        Link(destination: URL(string: "https://gohugo.io/templates/")!) {
                            Label("Hugo Templates Docs", systemImage: "book")
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

/// NSTextView with Go template syntax highlighting
struct GoTemplateTextView: NSViewRepresentable {
    @Binding var text: String
    let onTextChange: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = GoTemplateSyntaxTextView()

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.documentView = textView

        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.autoresizingMask = [.width]
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        textView.delegate = context.coordinator
        textView.string = text
        textView.highlightSyntax()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? GoTemplateSyntaxTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.highlightSyntax()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GoTemplateTextView

        init(_ parent: GoTemplateTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onTextChange()

            if let goTextView = textView as? GoTemplateSyntaxTextView {
                goTextView.highlightSyntax()
            }
        }
    }
}

/// Custom NSTextView subclass with Go template syntax highlighting
class GoTemplateSyntaxTextView: NSTextView {

    // Colors for syntax highlighting
    private let templateActionColor = NSColor.systemPurple
    private let templateVariableColor = NSColor.systemBlue
    private let templateCommentColor = NSColor.systemGreen
    private let stringColor = NSColor.systemRed
    private let htmlTagColor = NSColor.systemOrange

    func highlightSyntax() {
        guard let textStorage = textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)

        // Reset to default
        textStorage.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)

        let content = string

        // Highlight Go template expressions: {{ ... }}
        highlightPattern(#"\{\{.*?\}\}"#, color: templateActionColor, in: content)

        // Highlight template comments: {{/* ... */}}
        highlightPattern(#"\{\{/\*.*?\*/\}\}"#, color: templateCommentColor, in: content)

        // Highlight HTML tags
        highlightPattern(#"</?[a-zA-Z][^>]*>"#, color: htmlTagColor, in: content)

        // Highlight strings within templates
        highlightPattern(#"\"[^\"]*\""#, color: stringColor, in: content)
    }

    private func highlightPattern(_ pattern: String, color: NSColor, in content: String) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let textStorage = textStorage else { return }

        let fullRange = NSRange(location: 0, length: content.utf16.count)
        let matches = regex.matches(in: content, range: fullRange)

        for match in matches {
            textStorage.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}
```

---

### Step 7.3: Create Template Browser

**Create new file:** `Victor/Views/Templates/TemplateBrowserView.swift`

```swift
import SwiftUI

/// Browser for Hugo templates organized by category
struct TemplateBrowserView: View {
    let layoutsURL: URL
    @State private var templates: [HugoTemplate] = []
    @State private var selectedTemplate: HugoTemplate?
    @State private var isLoading = true
    @State private var groupByCategory = true

    var groupedTemplates: [HugoTemplate.Category: [HugoTemplate]] {
        Dictionary(grouping: templates) { $0.category }
    }

    var body: some View {
        HSplitView {
            // Template list
            VStack(spacing: 0) {
                templateListHeader
                Divider()

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    templateList
                }
            }
            .frame(minWidth: 200, maxWidth: 300)

            // Template editor
            if let template = selectedTemplate {
                TemplateEditorView(
                    template: template,
                    onSave: { await saveTemplate(template) },
                    allPartials: templates.filter { $0.category == .partial }.map { $0.url.lastPathComponent }
                )
            } else {
                Text("Select a template to edit")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await loadTemplates() }
    }

    private var templateListHeader: some View {
        HStack {
            Text("Templates")
                .font(.headline)
            Spacer()
            Toggle(isOn: $groupByCategory) {
                Image(systemName: "folder")
            }
            .toggleStyle(.button)
            .help("Group by category")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var templateList: some View {
        List(selection: $selectedTemplate) {
            if groupByCategory {
                ForEach(HugoTemplate.Category.allCases, id: \.self) { category in
                    if let categoryTemplates = groupedTemplates[category], !categoryTemplates.isEmpty {
                        Section(category.rawValue) {
                            ForEach(categoryTemplates) { template in
                                TemplateRow(template: template)
                            }
                        }
                    }
                }
            } else {
                ForEach(templates.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }) { template in
                    TemplateRow(template: template)
                }
            }
        }
    }

    private func loadTemplates() async {
        isLoading = true
        defer { isLoading = false }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: layoutsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        var loaded: [HugoTemplate] = []

        for case let url as URL in enumerator {
            guard url.pathExtension == "html" else { continue }
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                loaded.append(HugoTemplate(url: url, content: content))
            }
        }

        templates = loaded
    }

    private func saveTemplate(_ template: HugoTemplate) async {
        do {
            try template.content.write(to: template.url, atomically: true, encoding: .utf8)
            template.originalContent = template.content
        } catch {
            print("Failed to save template: \(error)")
        }
    }
}

struct TemplateRow: View {
    let template: HugoTemplate

    var body: some View {
        HStack {
            Image(systemName: categoryIcon)
                .foregroundStyle(categoryColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(template.url.lastPathComponent)
                    if template.hasUnsavedChanges {
                        Circle().fill(.orange).frame(width: 6, height: 6)
                    }
                }

                if !template.includedPartials.isEmpty {
                    Text("Includes \(template.includedPartials.count) partials")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var categoryIcon: String {
        switch template.category {
        case .base: return "rectangle.stack"
        case .list: return "list.bullet.rectangle"
        case .single: return "doc.richtext"
        case .partial: return "square.on.square"
        case .shortcode: return "chevron.left.forwardslash.chevron.right"
        case .taxonomy: return "tag"
        case .other: return "doc"
        }
    }

    private var categoryColor: Color {
        switch template.category {
        case .base: return .purple
        case .list: return .blue
        case .single: return .green
        case .partial: return .orange
        case .shortcode: return .pink
        case .taxonomy: return .teal
        case .other: return .secondary
        }
    }
}
```

---

### Step 7.4: Testing Checklist for Phase 7

- [ ] Template browser shows all templates from layouts/
- [ ] Templates grouped by category (base, list, single, partial, shortcode)
- [ ] Can toggle grouping on/off
- [ ] Template editor opens with syntax highlighting
- [ ] Go template expressions ({{ }}) highlighted in purple
- [ ] HTML tags highlighted in orange
- [ ] Strings highlighted in red
- [ ] Comments highlighted in green
- [ ] Inspector shows defined blocks
- [ ] Inspector shows included partials
- [ ] Insert menu adds common template snippets
- [ ] Can save templates with ⌘S
- [ ] Unsaved changes indicator works

---

## Phase 8: Hugo Server Integration

### Goal
Integrate Hugo's development server for live preview with build error display.

### Prerequisites
- Hugo must be installed on the system
- Understanding of Swift `Process` for spawning subprocesses

---

### Understanding Hugo Server

#### Hugo Dev Server Features
- Hot reload on file changes
- Draft content preview
- Fast incremental builds
- WebSocket for browser refresh
- Configurable port and bind address

#### Key Commands
```bash
hugo server                    # Start dev server
hugo server -D                 # Include drafts
hugo server --port 1313        # Custom port
hugo server --bind 0.0.0.0     # Network accessible
```

---

### Step 8.1: Create HugoServerService

**Create new file:** `Victor/Services/HugoServerService.swift`

```swift
import Foundation
import Combine

/// Service for managing Hugo development server
@MainActor
@Observable
class HugoServerService {
    // MARK: - State

    enum ServerState: Equatable {
        case stopped
        case starting
        case running(port: Int)
        case error(String)
    }

    var state: ServerState = .stopped
    var buildOutput: [BuildLogEntry] = []
    var lastError: BuildError?

    // MARK: - Configuration

    var port: Int = 1313
    var includeDrafts: Bool = true
    var includeFuture: Bool = false

    // MARK: - Private

    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var siteURL: URL?

    // MARK: - Public Methods

    /// Check if Hugo is installed
    func checkHugoInstallation() async -> HugoInstallation? {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["hugo", "version"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8),
                   process.terminationStatus == 0 {
                    // Parse version from output like "hugo v0.121.1+extended darwin/arm64..."
                    let version = parseHugoVersion(from: output)
                    continuation.resume(returning: HugoInstallation(
                        version: version,
                        isExtended: output.contains("+extended"),
                        path: "/usr/bin/env hugo"
                    ))
                } else {
                    continuation.resume(returning: nil)
                }
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// Start the Hugo development server
    func start(for siteURL: URL) async {
        guard case .stopped = state else { return }

        self.siteURL = siteURL
        state = .starting
        buildOutput = []
        lastError = nil

        // Find available port
        port = await findAvailablePort(starting: 1313)

        process = Process()
        process?.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process?.currentDirectoryURL = siteURL

        var args = ["hugo", "server", "--port", "\(port)"]
        if includeDrafts { args.append("-D") }
        if includeFuture { args.append("-F") }
        process?.arguments = args

        // Set up output handling
        outputPipe = Pipe()
        errorPipe = Pipe()
        process?.standardOutput = outputPipe
        process?.standardError = errorPipe

        // Handle output
        outputPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                Task { @MainActor in
                    self?.handleOutput(output)
                }
            }
        }

        errorPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                Task { @MainActor in
                    self?.handleError(output)
                }
            }
        }

        // Handle termination
        process?.terminationHandler = { [weak self] process in
            Task { @MainActor in
                if process.terminationStatus != 0 {
                    self?.state = .error("Server exited with code \(process.terminationStatus)")
                } else {
                    self?.state = .stopped
                }
            }
        }

        do {
            try process?.run()
            // Wait briefly for server to start
            try await Task.sleep(for: .seconds(1))
            state = .running(port: port)
        } catch {
            state = .error("Failed to start server: \(error.localizedDescription)")
        }
    }

    /// Stop the Hugo server
    func stop() {
        process?.terminate()
        process = nil
        outputPipe = nil
        errorPipe = nil
        state = .stopped
    }

    /// Restart the server
    func restart() async {
        guard let url = siteURL else { return }
        stop()
        try? await Task.sleep(for: .milliseconds(500))
        await start(for: url)
    }

    /// Get the server URL
    var serverURL: URL? {
        guard case .running(let port) = state else { return nil }
        return URL(string: "http://localhost:\(port)")
    }

    // MARK: - Private Methods

    private func handleOutput(_ output: String) {
        // Parse Hugo's output for status messages
        let lines = output.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            let entry = BuildLogEntry(
                timestamp: Date(),
                level: .info,
                message: line
            )
            buildOutput.append(entry)

            // Detect server ready
            if line.contains("Web Server is available at") {
                if case .starting = state {
                    state = .running(port: port)
                }
            }
        }

        // Limit log size
        if buildOutput.count > 500 {
            buildOutput.removeFirst(100)
        }
    }

    private func handleError(_ output: String) {
        let lines = output.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            let entry = BuildLogEntry(
                timestamp: Date(),
                level: .error,
                message: line
            )
            buildOutput.append(entry)

            // Parse build errors
            if let error = parseBuildError(from: line) {
                lastError = error
            }
        }
    }

    private func parseBuildError(from line: String) -> BuildError? {
        // Hugo error format: ERROR 2024/01/01 12:00:00 file.html:10:5: error message
        let pattern = #"ERROR.*?([^:]+):(\d+)(?::(\d+))?:\s*(.+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }

        guard let fileRange = Range(match.range(at: 1), in: line),
              let lineRange = Range(match.range(at: 2), in: line),
              let msgRange = Range(match.range(at: 4), in: line) else {
            return nil
        }

        let column = match.range(at: 3).location != NSNotFound
            ? Range(match.range(at: 3), in: line).flatMap { Int(line[$0]) }
            : nil

        return BuildError(
            file: String(line[fileRange]),
            line: Int(line[lineRange]) ?? 0,
            column: column,
            message: String(line[msgRange])
        )
    }

    private func parseHugoVersion(from output: String) -> String {
        // Extract version from "hugo v0.121.1+extended darwin/arm64..."
        let pattern = #"v(\d+\.\d+\.\d+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
           let range = Range(match.range(at: 1), in: output) {
            return String(output[range])
        }
        return "unknown"
    }

    private func findAvailablePort(starting: Int) async -> Int {
        // Simple implementation - try ports sequentially
        for port in starting..<(starting + 100) {
            if await isPortAvailable(port) {
                return port
            }
        }
        return starting
    }

    private func isPortAvailable(_ port: Int) async -> Bool {
        // Try to bind to port briefly
        let socket = socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        defer { close(socket) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        return result == 0
    }
}

// MARK: - Supporting Types

struct HugoInstallation {
    let version: String
    let isExtended: Bool
    let path: String
}

struct BuildLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String

    enum LogLevel {
        case info
        case warning
        case error
    }
}

struct BuildError: Identifiable {
    let id = UUID()
    let file: String
    let line: Int
    let column: Int?
    let message: String
}
```

---

### Step 8.2: Create ServerControlView

**Create new file:** `Victor/Views/Server/ServerControlView.swift`

```swift
import SwiftUI

/// Control panel for Hugo development server
struct ServerControlView: View {
    @Bindable var serverService: HugoServerService
    let siteURL: URL

    @State private var hugoInstallation: HugoInstallation?
    @State private var showBuildLog = false

    var body: some View {
        VStack(spacing: 0) {
            serverToolbar
            Divider()

            if showBuildLog {
                buildLogView
            }
        }
    }

    private var serverToolbar: some View {
        HStack {
            // Server status
            serverStatusIndicator

            Divider().frame(height: 20)

            // Port display
            if case .running(let port) = serverService.state {
                Button {
                    if let url = serverService.serverURL {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("localhost:\(port)", systemImage: "globe")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            // Options
            Toggle("Drafts", isOn: $serverService.includeDrafts)
                .toggleStyle(.button)
                .disabled(isRunning)

            Toggle("Future", isOn: $serverService.includeFuture)
                .toggleStyle(.button)
                .disabled(isRunning)

            Divider().frame(height: 20)

            // Build log toggle
            Toggle(isOn: $showBuildLog) {
                HStack {
                    Image(systemName: "terminal")
                    if let error = serverService.lastError {
                        Circle().fill(.red).frame(width: 8, height: 8)
                    }
                }
            }
            .toggleStyle(.button)

            Divider().frame(height: 20)

            // Control buttons
            if isRunning {
                Button {
                    serverService.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Button {
                    Task { await serverService.restart() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            } else {
                Button {
                    Task { await serverService.start(for: siteURL) }
                } label: {
                    Label("Start Server", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(hugoInstallation == nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .task {
            hugoInstallation = await serverService.checkHugoInstallation()
        }
    }

    private var serverStatusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(statusText)
                .font(.caption)
        }
    }

    private var isRunning: Bool {
        if case .running = serverService.state { return true }
        return false
    }

    private var statusColor: Color {
        switch serverService.state {
        case .stopped: return .secondary
        case .starting: return .yellow
        case .running: return .green
        case .error: return .red
        }
    }

    private var statusText: String {
        switch serverService.state {
        case .stopped: return "Stopped"
        case .starting: return "Starting..."
        case .running: return "Running"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private var buildLogView: some View {
        VStack(spacing: 0) {
            // Error banner if present
            if let error = serverService.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("\(error.file):\(error.line) - \(error.message)")
                        .font(.caption)
                    Spacer()
                    Button("Go to Error") {
                        // Navigate to error location
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(8)
                .background(.red.opacity(0.1))
            }

            // Log entries
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(serverService.buildOutput) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .trailing)

                                Circle()
                                    .fill(logLevelColor(entry.level))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 5)

                                Text(entry.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: serverService.buildOutput.count) { _, _ in
                    if let last = serverService.buildOutput.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .frame(height: 150)
        }
    }

    private func logLevelColor(_ level: BuildLogEntry.LogLevel) -> Color {
        switch level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}
```

---

### Step 8.3: Create LivePreviewPanel

**Create new file:** `Victor/Views/Server/LivePreviewPanel.swift`

```swift
import SwiftUI
import WebKit

/// Live preview panel using Hugo dev server
struct LivePreviewPanel: View {
    @Bindable var serverService: HugoServerService
    let currentPath: String?  // Current content file path for navigation

    @State private var webView: WKWebView?
    @State private var isRefreshing = false

    var body: some View {
        VStack(spacing: 0) {
            previewToolbar
            Divider()

            if case .running = serverService.state {
                LivePreviewWebView(
                    url: previewURL,
                    webView: $webView
                )
            } else {
                notRunningPlaceholder
            }
        }
    }

    private var previewURL: URL? {
        guard let serverURL = serverService.serverURL else { return nil }

        // If we have a current content path, try to navigate to it
        if let path = currentPath {
            // Convert content/posts/my-post.md to /posts/my-post/
            let urlPath = path
                .replacingOccurrences(of: "content/", with: "/")
                .replacingOccurrences(of: ".md", with: "/")
                .replacingOccurrences(of: "_index", with: "")
                .replacingOccurrences(of: "index", with: "")
            return serverURL.appendingPathComponent(urlPath)
        }

        return serverURL
    }

    private var previewToolbar: some View {
        HStack {
            Image(systemName: "globe")
                .foregroundStyle(.blue)

            Text("Live Preview")
                .font(.headline)

            if case .running(let port) = serverService.state {
                Text("localhost:\(port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Navigation
            Button {
                webView?.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!(webView?.canGoBack ?? false))

            Button {
                webView?.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!(webView?.canGoForward ?? false))

            Divider().frame(height: 20)

            // Refresh
            Button {
                isRefreshing = true
                webView?.reload()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isRefreshing = false
                }
            } label: {
                if isRefreshing {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .keyboardShortcut("r", modifiers: .command)

            // Open in browser
            Button {
                if let url = previewURL {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "safari")
            }
            .help("Open in browser")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var notRunningPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Start Hugo Server for Live Preview")
                .font(.headline)

            Text("Live preview shows your site exactly as it will appear when published")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// WKWebView wrapper for live preview
struct LivePreviewWebView: NSViewRepresentable {
    let url: URL?
    @Binding var webView: WKWebView?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)

        DispatchQueue.main.async {
            self.webView = webView
        }

        if let url = url {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Reload if URL changed significantly
        if let url = url,
           webView.url?.host != url.host {
            webView.load(URLRequest(url: url))
        }
    }
}
```

---

### Step 8.4: Integrate Server into Main App

Add to SiteViewModel:

```swift
// Add property:
var hugoServerService = HugoServerService()

// Add cleanup on site change:
func openSite(_ url: URL) async {
    // Stop any running server
    hugoServerService.stop()

    // ... rest of existing implementation
}
```

Add to ContentView or main layout:

```swift
// Add server control bar at bottom of window
VStack(spacing: 0) {
    // ... existing content

    Divider()

    ServerControlView(
        serverService: siteViewModel.hugoServerService,
        siteURL: siteViewModel.currentSite?.url ?? URL(fileURLWithPath: "/")
    )
}
```

---

### Step 8.5: Testing Checklist for Phase 8

- [ ] Hugo installation detected on launch
- [ ] Version and extended status displayed
- [ ] Can start server with Start button
- [ ] Server status indicator shows correct state
- [ ] Port displayed when running
- [ ] Can open preview in browser
- [ ] Build log shows Hugo output
- [ ] Build errors parsed and displayed
- [ ] Error banner shows file/line/message
- [ ] Can stop server with Stop button
- [ ] Can restart server
- [ ] Drafts toggle works
- [ ] Future toggle works
- [ ] Live preview shows site content
- [ ] Live preview navigation works
- [ ] Refresh button reloads preview
- [ ] Server stops when switching sites

---

## Implementation Priority Recommendation

Based on user value and implementation complexity:

| Priority | Phase | Rationale |
|----------|-------|-----------|
| 1 | **Phase 6** | Immediate benefit for content creators, visual asset management |
| 2 | **Phase 5** | Natural extension of existing editors, moderate complexity |
| 3 | **Phase 8** | High user value but adds cognitive complexity for a CMS |
| 4 | **Phase 7** | Most complex (syntax highlighting), niche use case |

**Note**: Phase 5 and Phase 6 can be implemented in parallel since they don't share dependencies.

---

## General Implementation Guidelines

### Adding New Files
1. Create the file in the appropriate directory
2. Run `xcodegen generate` to update the Xcode project
3. Build to verify: `xcodebuild -project Victor.xcodeproj -scheme Victor build`

### Testing Changes
1. Open the app in Xcode and run (⌘R)
2. Open a real Hugo site folder
3. Test the specific feature you implemented
4. Verify existing functionality still works

### Code Style
- Use `@MainActor @Observable` for all ViewModels
- Use `async/await` with `Task.detached` for file I/O
- Use `@Bindable` for binding to `@Observable` objects
- Follow existing patterns in the codebase

### Error Handling
- Always use `do/catch` for throwing functions
- Display errors to users via state properties
- Log errors with `print()` for debugging

### Memory Management
- Use `weak` references in closures when capturing `self`
- Cancel ongoing tasks when views disappear
- Use LRU caching for loaded file content
