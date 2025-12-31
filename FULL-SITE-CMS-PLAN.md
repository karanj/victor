# Victor Full-Site Hugo CMS Extension Plan

## Overview

Transform Victor from a content-only markdown editor into a comprehensive Hugo site CMS that can display, view, and edit all site files while providing a discoverable GUI for Hugo configuration.

**Current State:** Victor only scans `content/` directory and displays `.md` files
**Target State:** Full site visibility with file-type-aware viewing/editing and GUI config management

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

## Phase 2: Multi-File Viewing (Read Support)

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

## Phase 3: Text File Editing (Write Support)

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

## Phase 4: Hugo Config GUI Editor

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

## Phases 5-8: Future Implementation

### Phase 5: Data & Archetypes Management
- Create `DataFileEditorView` for editing YAML/JSON data files in `data/`
- Create `ArchetypeManagerView` for managing content templates in `archetypes/`
- Create `TranslationEditorView` for i18n files

### Phase 6: Asset Management
- Create `AssetBrowserView` with grid/list views for `static/` and `assets/`
- Add thumbnail generation for images
- Add drag & drop support for inserting images into markdown

### Phase 7: Template Editing
- Create `TemplateEditorView` for HTML templates in `layouts/`
- Add Go template syntax awareness
- Show template inheritance hierarchy

### Phase 8: Hugo Server Integration
- Create `HugoServerService` to manage the Hugo development server
- Add live preview using Hugo's built-in server
- Show build errors in the UI

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
