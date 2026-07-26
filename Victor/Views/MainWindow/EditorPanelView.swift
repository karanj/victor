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

    // Editor preferences (shared with Preferences window via AppSettings)
    @Bindable private var settings = AppSettings.shared

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

            // Toolbar. Takes the viewModel rather than plain isSaving/
            // hasUnsavedChanges values: reading those here would make THIS body
            // (and everything below it) re-evaluate on every keystroke. The
            // toolbar's leaf views read them instead (keystroke-lag fix, part 2).
            EditorToolbar(
                isLivePreviewEnabled: $siteViewModel.isLivePreviewEnabled,
                showShortcodePicker: $showShortcodePicker,
                viewModel: viewModel,
                reduceMotion: reduceMotion,
                contentPaths: siteViewModel.contentPaths,
                onSave: { Task { await viewModel.save() } },
                onFormat: { format in
                    editorCoordinator?.applyFormat(format)
                },
                onInsertShortcode: { shortcodeText in
                    editorCoordinator?.insertText(shortcodeText)
                }
            )

            // Markdown Editor (takes priority)
            EditorTextView(
                text: $viewModel.editableContent,
                highlightCurrentLine: settings.highlightCurrentLine,
                fontSize: settings.editorFontSize,
                fontName: settings.editorFontName,
                checkSpellingWhileTyping: settings.checkSpellingWhileTyping,
                checkGrammarWithSpelling: settings.checkGrammarWithSpelling,
                correctSpellingAutomatically: settings.correctSpellingAutomatically,
                useTextReplacement: settings.useTextReplacement,
                onCoordinatorReady: { coordinator in
                    editorCoordinator = coordinator
                },
                onCursorPositionChange: { position in
                    viewModel.updateCursorPosition(line: position.line, column: position.column)
                },
                onShowShortcodePicker: {
                    showShortcodePicker = true
                },
                // W3.3 (victor-dnd): lets EditorTextView's drag handler resolve where a
                // dropped image should be copied (page bundle vs static/) - see
                // ImageDropPathResolver. Only new arguments added to this existing call.
                fileNode: fileNode,
                siteViewModel: siteViewModel
            )
            .opacity(contentOpacity)

            // Status bar with cursor position. Wrapped so the per-keystroke
            // cursorLine/cursorColumn reads invalidate only this leaf, not the
            // whole panel body (keystroke-lag fix, part 2).
            EditorStatusBarView(viewModel: viewModel)

            // Bottom Frontmatter Panel (collapsible)
            if let frontmatter = contentFile.frontmatter {
                FrontmatterBottomPanel(
                    frontmatter: frontmatter,
                    isExpanded: $isFrontmatterExpanded
                )
            }
        }
        .onAppear {
            // Fade in editor content when view appears
            if reduceMotion {
                contentOpacity = 1
            } else {
                withAnimation(.easeInOut(duration: AppConstants.Animation.fast)) {
                    contentOpacity = 1
                }
            }
        }
        .onDisappear {
            // Release reference to pending tasks when editor is dismissed
            viewModel.cleanup()
        }
        .navigationTitle(viewModel.navigationTitle)
        // EditorActions is Equatable by editorID, so re-running this body doesn't
        // invalidate VictorApp's @FocusedValue (and the whole .commands tree) - only a
        // file switch does. hasUnsavedChanges consults isFileModified, not
        // viewModel.hasUnsavedChanges, so menu validation never depends on typing state.
        .focusedValue(\.editorActions, EditorActions(
            editorID: fileNode.id,
            formatting: { format in
                editorCoordinator?.applyFormat(format)
            },
            showShortcodePicker: {
                showShortcodePicker = true
            },
            save: {
                await viewModel.save()
            },
            revert: {
                await viewModel.reloadFromDisk()
            },
            hasUnsavedChanges: {
                siteViewModel.isFileModified(fileNode.id)
            }
        ))
        // When the selected file changes, reset the editor view model so it
        // points at the new file node and content instead of the previous one.
        .onChange(of: contentFile.id) { _, _ in
            // Release old ViewModel's task reference (save continues in background)
            viewModel.cleanup()
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
                withAnimation(.easeInOut(duration: AppConstants.Animation.fast)) {
                    contentOpacity = 1
                }
            }
        }
        // Update content when file changes
        .onChange(of: contentFile.markdownContent) { _, newValue in
            viewModel.updateContent(from: newValue)
        }
        // Deliberately no .onChange(of: viewModel.editableContent) - that read would
        // re-register this whole body against per-keystroke state. Typing is handled in
        // the editableContent setter. Frontmatter uses a version counter to avoid
        // snapshot comparison on every render.
        .onChange(of: contentFile.frontmatter?.version) { _, _ in
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
    }
}

// MARK: - Editor Toolbar

struct EditorToolbar: View {
    @Binding var isLivePreviewEnabled: Bool
    @Binding var showShortcodePicker: Bool
    /// Passed through to SaveButton, which reads the per-keystroke save state
    /// (isSaving/showSavedIndicator/hasUnsavedChanges) in its own body so those
    /// reads invalidate only that leaf (keystroke-lag fix, part 2).
    let viewModel: EditorViewModel
    let reduceMotion: Bool
    let contentPaths: [ContentPathSuggestion]
    let onSave: () -> Void
    let onFormat: (MarkdownFormat) -> Void
    let onInsertShortcode: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            formattingGroups
            Spacer()
            LivePreviewToggle(isEnabled: $isLivePreviewEnabled)
            actionSeparator
            SaveButton(
                viewModel: viewModel,
                reduceMotion: reduceMotion,
                onSave: onSave
            )
        }
        .padding(.horizontal, AppConstants.Toolbar.horizontalPadding)
        .padding(.vertical, AppConstants.Toolbar.verticalPadding)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Formatting Groups

    private var formattingGroups: some View {
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
                Button(action: { showShortcodePicker = true }) {
                    Label("Shortcode", systemImage: "curlybraces")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Insert Shortcode (⌘⇧K)")
                .accessibilityLabel("Insert Shortcode")
                .popover(isPresented: $showShortcodePicker) {
                    ShortcodePickerView(contentPaths: contentPaths) { shortcodeText in
                        onInsertShortcode(shortcodeText)
                    }
                }
            }
        }
    }

    private var actionSeparator: some View {
        Divider()
            .frame(height: AppConstants.Toolbar.actionSeparatorHeight)
            .padding(.horizontal, AppConstants.Toolbar.horizontalPadding)
    }
}

// MARK: - Toolbar Components

/// A group of toolbar buttons with consistent spacing
struct ToolbarGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: AppConstants.Toolbar.groupSpacing) {
            content
        }
    }
}

/// Visual separator between toolbar groups
struct ToolbarSeparator: View {
    var body: some View {
        Divider()
            .frame(height: AppConstants.Toolbar.separatorHeight)
            .padding(.horizontal, AppConstants.Toolbar.separatorPadding)
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
        .accessibilityLabel(label)
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
        .frame(width: AppConstants.Toolbar.headingMenuWidth)
    }
}

/// Toggle button for enabling/disabling live preview
struct LivePreviewToggle: View {
    @Binding var isEnabled: Bool

    var body: some View {
        Button(action: { isEnabled.toggle() }) {
            Label(
                isEnabled ? "Live Preview On" : "Live Preview Off",
                systemImage: isEnabled ? "eye.fill" : "eye.slash.fill"
            )
            .labelStyle(.titleAndIcon)
            .font(.callout)
        }
        .buttonStyle(.bordered)
        .help(isEnabled ? "Disable live preview" : "Enable live preview")
    }
}

/// Save button with animated indicator. Reads per-keystroke state in its OWN body -
/// taking `hasUnsavedChanges` as a plain value would force every ancestor to
/// re-evaluate per keystroke. This leaf doing so is cheap; EditorPanelView is not.
struct SaveButton: View {
    let viewModel: EditorViewModel
    let reduceMotion: Bool
    let onSave: () -> Void

    @State private var indicatorScale: CGFloat = 0.5
    @State private var indicatorOpacity: Double = 0

    var body: some View {
        if viewModel.showSavedIndicator {
            savedIndicator
        } else if viewModel.isSaving {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Saving")
        } else {
            saveButton
        }
    }

    private var savedIndicator: some View {
        Label("Saved", systemImage: "checkmark.circle.fill")
            .foregroundStyle(Color.Status.saved)
            .font(.callout)
            .scaleEffect(indicatorScale)
            .opacity(indicatorOpacity)
            .onAppear {
                if reduceMotion {
                    indicatorScale = 1.0
                    indicatorOpacity = 1.0
                } else {
                    withAnimation(.spring(
                        response: AppConstants.Toolbar.saveSpringResponse,
                        dampingFraction: AppConstants.Toolbar.saveSpringDamping
                    )) {
                        indicatorScale = 1.0
                        indicatorOpacity = 1.0
                    }
                }
            }
            .onDisappear {
                indicatorScale = 0.5
                indicatorOpacity = 0
            }
    }

    private var saveButton: some View {
        Button(action: onSave) {
            Label("Save", systemImage: "arrow.down.doc.fill")
                .labelStyle(.titleAndIcon)
                .font(.callout)
        }
        // No .keyboardShortcut here - File > Save (Cmd+S) is the single owner,
        // routed through the focusedValue(\.editorActions) published above.
        .disabled(!viewModel.hasUnsavedChanges)
        .buttonStyle(.bordered)
    }
}

/// Leaf wrapper isolating the per-keystroke cursorLine/cursorColumn reads from
/// EditorPanelView's body (keystroke-lag fix, part 2). EditorStatusBar itself
/// stays a dumb Int-taking component (previewable without a viewModel).
private struct EditorStatusBarView: View {
    let viewModel: EditorViewModel

    var body: some View {
        EditorStatusBar(
            cursorLine: viewModel.cursorLine,
            cursorColumn: viewModel.cursorColumn
        )
    }
}
