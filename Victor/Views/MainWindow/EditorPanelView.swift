import SwiftUI

// MARK: - Editor Panel

struct EditorPanelView: View {
    let contentFile: ContentFile
    let fileNode: FileNode
    @Bindable var siteViewModel: SiteViewModel

    // ViewModel for editor business logic
    @State private var viewModel: EditorViewModel

    // View-specific state (UI coordination, not business logic)
    @State private var editorCoordinator: EditorTextView.Coordinator?
    @State private var isFrontmatterExpanded = false
    @State private var contentOpacity: Double = 0
    @State private var showShortcodePicker = false

    // Editor preferences (using @AppStorage for live updates from Preferences window)
    @AppStorage("highlightCurrentLine") private var highlightCurrentLine = true
    @AppStorage("editorFontSize") private var editorFontSize: Double = 13.0

    // Accessibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(contentFile: ContentFile, fileNode: FileNode, siteViewModel: SiteViewModel) {
        self.contentFile = contentFile
        self.fileNode = fileNode
        self.siteViewModel = siteViewModel
        // Initialize view model
        _viewModel = State(initialValue: EditorViewModel(
            fileNode: fileNode,
            contentFile: contentFile,
            siteViewModel: siteViewModel
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumb navigation
            BreadcrumbBar(fileNode: fileNode, siteViewModel: siteViewModel)

            // Toolbar
            EditorToolbar(
                isLivePreviewEnabled: $siteViewModel.isLivePreviewEnabled,
                showShortcodePicker: $showShortcodePicker,
                isSaving: viewModel.isSaving,
                showSavedIndicator: viewModel.showSavedIndicator,
                hasUnsavedChanges: viewModel.hasUnsavedChanges,
                reduceMotion: reduceMotion,
                onSave: { Task { await viewModel.save() } },
                onFormat: { format in
                    editorCoordinator?.applyFormat(format)
                }
            )

            // Markdown Editor (takes priority)
            EditorTextView(
                text: $viewModel.editableContent,
                highlightCurrentLine: highlightCurrentLine,
                fontSize: editorFontSize,
                onCoordinatorReady: { coordinator in
                    editorCoordinator = coordinator
                },
                onCursorPositionChange: { position in
                    viewModel.updateCursorPosition(line: position.line, column: position.column)
                }
            )
            .opacity(contentOpacity)

            // Status bar with word count, character count, and cursor position
            EditorStatusBar(
                wordCount: viewModel.wordCount,
                characterCount: viewModel.characterCount,
                cursorLine: viewModel.cursorLine,
                cursorColumn: viewModel.cursorColumn
            )

            // Bottom Frontmatter Panel (collapsible)
            if contentFile.frontmatter != nil {
                FrontmatterBottomPanel(
                    frontmatter: contentFile.frontmatter!,
                    isExpanded: $isFrontmatterExpanded
                )
            }
        }
        .onAppear {
            // Fade in editor content when view appears
            if reduceMotion {
                contentOpacity = 1
            } else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    contentOpacity = 1
                }
            }
        }
        .navigationTitle(viewModel.navigationTitle)
        .navigationSubtitle(viewModel.navigationSubtitle)
        // Provide formatting function to focused value system for keyboard shortcuts
        .focusedValue(\.editorFormatting) { format in
            editorCoordinator?.applyFormat(format)
        }
        // Provide shortcode picker toggle for keyboard shortcut
        .focusedValue(\.showShortcodePicker) {
            showShortcodePicker = true
        }
        // When the selected file changes, reset the editor view model so it
        // points at the new file node and content instead of the previous one.
        .onChange(of: contentFile.id) { _, _ in
            // Reset opacity for fade-in animation on new file
            contentOpacity = 0
            viewModel = EditorViewModel(
                fileNode: fileNode,
                contentFile: contentFile,
                siteViewModel: siteViewModel
            )
            // Trigger fade-in after reset
            if reduceMotion {
                contentOpacity = 1
            } else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    contentOpacity = 1
                }
            }
        }
        // Update content when file changes
        .onChange(of: contentFile.markdownContent) { _, newValue in
            viewModel.updateContent(from: newValue)
        }
        // Handle content changes (live preview + auto-save)
        .onChange(of: viewModel.editableContent) { _, _ in
            viewModel.handleContentChange()
        }
        // Also handle frontmatter changes
        .onChange(of: contentFile.frontmatter?.title) { _, _ in
            viewModel.handleContentChange()
        }
        .onChange(of: contentFile.frontmatter?.date) { _, _ in
            viewModel.handleContentChange()
        }
        .onChange(of: contentFile.frontmatter?.draft) { _, _ in
            viewModel.handleContentChange()
        }
        .onChange(of: contentFile.frontmatter?.tags) { _, _ in
            viewModel.handleContentChange()
        }
        .onChange(of: contentFile.frontmatter?.categories) { _, _ in
            viewModel.handleContentChange()
        }
        .onChange(of: contentFile.frontmatter?.description) { _, _ in
            viewModel.handleContentChange()
        }
        .alert("File Modified Externally", isPresented: $viewModel.showConflictAlert) {
            Button("Reload from Disk") {
                Task {
                    await viewModel.reloadFromDisk()
                }
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("This file was modified by another application. Auto-save has been cancelled. You can reload the file to see external changes, or keep editing to manually save your version.")
        }
        .sheet(isPresented: $showShortcodePicker) {
            ShortcodePickerView { shortcodeText in
                editorCoordinator?.insertText(shortcodeText)
            }
        }
    }
}

// MARK: - Editor Toolbar

struct EditorToolbar: View {
    @Binding var isLivePreviewEnabled: Bool
    @Binding var showShortcodePicker: Bool
    let isSaving: Bool
    let showSavedIndicator: Bool
    let hasUnsavedChanges: Bool
    let reduceMotion: Bool
    let onSave: () -> Void
    let onFormat: (MarkdownFormat) -> Void

    // Animation state for save indicator
    @State private var saveIndicatorScale: CGFloat = 0.5
    @State private var saveIndicatorOpacity: Double = 0

    var body: some View {
        HStack(spacing: 0) {
            // Group 1: Text Formatting
            ToolbarGroup {
                ToolbarButton(icon: "bold", label: "Bold", help: "Bold (⌘B)") {
                    onFormat(.bold)
                }
                ToolbarButton(icon: "italic", label: "Italic", help: "Italic (⌘I)") {
                    onFormat(.italic)
                }
            }

            ToolbarSeparator()

            // Group 2: Headings
            ToolbarGroup {
                HeadingMenu(onFormat: onFormat)
            }

            ToolbarSeparator()

            // Group 3: Lists
            ToolbarGroup {
                ToolbarButton(icon: "list.bullet", label: "Bullet List", help: "Bullet List") {
                    onFormat(.unorderedList)
                }
                ToolbarButton(icon: "list.number", label: "Numbered List", help: "Numbered List") {
                    onFormat(.orderedList)
                }
            }

            ToolbarSeparator()

            // Group 4: Block Elements
            ToolbarGroup {
                ToolbarButton(icon: "chevron.left.forwardslash.chevron.right", label: "Code", help: "Code Block") {
                    onFormat(.code)
                }
                ToolbarButton(icon: "text.quote", label: "Quote", help: "Block Quote (⌘')") {
                    onFormat(.blockquote)
                }
            }

            ToolbarSeparator()

            // Group 5: Insert Elements
            ToolbarGroup {
                ToolbarButton(icon: "link", label: "Link", help: "Insert Link (⌘K)") {
                    onFormat(.link)
                }
                ToolbarButton(icon: "photo", label: "Image", help: "Insert Image (⌘⇧I)") {
                    onFormat(.image)
                }
                ToolbarButton(icon: "curlybraces", label: "Shortcode", help: "Insert Shortcode (⌘⇧K)") {
                    showShortcodePicker = true
                }
            }

            Spacer()

            // Live Preview Toggle
            Button(action: { isLivePreviewEnabled.toggle() }) {
                Label(
                    isLivePreviewEnabled ? "Live Preview On" : "Live Preview Off",
                    systemImage: isLivePreviewEnabled ? "eye.fill" : "eye.slash.fill"
                )
                .labelStyle(.titleAndIcon)
                .font(.callout)
            }
            .buttonStyle(.bordered)
            .help(isLivePreviewEnabled ? "Disable live preview" : "Enable live preview")

            // Action separator (thicker visual break)
            Divider()
                .frame(height: 24)
                .padding(.horizontal, 12)

            // Save Button
            if showSavedIndicator {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
                    .scaleEffect(saveIndicatorScale)
                    .opacity(saveIndicatorOpacity)
                    .onAppear {
                        if reduceMotion {
                            saveIndicatorScale = 1.0
                            saveIndicatorOpacity = 1.0
                        } else {
                            // Pop-in animation
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                saveIndicatorScale = 1.0
                                saveIndicatorOpacity = 1.0
                            }
                        }
                    }
                    .onDisappear {
                        // Reset for next appearance
                        saveIndicatorScale = 0.5
                        saveIndicatorOpacity = 0
                    }
            } else if isSaving {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(action: onSave) {
                    Label("Save", systemImage: "arrow.down.doc.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.callout)
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!hasUnsavedChanges)
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

// MARK: - Toolbar Components

/// A group of toolbar buttons with consistent spacing
struct ToolbarGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 4) {
            content
        }
    }
}

/// Visual separator between toolbar groups
struct ToolbarSeparator: View {
    var body: some View {
        Divider()
            .frame(height: 20)
            .padding(.horizontal, 8)
    }
}

/// Standard toolbar button with icon, label, and tooltip
struct ToolbarButton: View {
    let icon: String
    let label: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .help(help)
    }
}

/// Heading dropdown menu with H1-H6 options
struct HeadingMenu: View {
    let onFormat: (MarkdownFormat) -> Void

    var body: some View {
        Menu {
            Button("Heading 1") { onFormat(.heading(level: 1)) }
            Button("Heading 2") { onFormat(.heading(level: 2)) }
            Button("Heading 3") { onFormat(.heading(level: 3)) }
            Button("Heading 4") { onFormat(.heading(level: 4)) }
            Button("Heading 5") { onFormat(.heading(level: 5)) }
            Button("Heading 6") { onFormat(.heading(level: 6)) }
        } label: {
            Label("Heading", systemImage: "h.square")
        }
        .buttonStyle(.bordered)
        .help("Insert Heading (H1-H6)")
        .frame(width: 100)
    }
}
