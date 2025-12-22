import SwiftUI

struct ContentView: View {
    @Bindable var siteViewModel: SiteViewModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar - File navigation
            SidebarView(siteViewModel: siteViewModel)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        } content: {
            // Editor Panel - Markdown content (Phase 2: Editable)
            if let selectedNode = siteViewModel.selectedNode,
               let contentFile = selectedNode.contentFile {
                EditorPanelView(
                    contentFile: contentFile,
                    fileNode: selectedNode,
                    siteViewModel: siteViewModel
                )
            } else {
                ContentUnavailableView(
                    "No File Selected",
                    systemImage: "doc.text",
                    description: Text("Select a markdown file from the sidebar")
                )
            }
        } detail: {
            // Preview Panel - Live markdown preview
            if let selectedNode = siteViewModel.selectedNode,
               let contentFile = selectedNode.contentFile {
                PreviewPanel(contentFile: contentFile, siteViewModel: siteViewModel)
            } else {
                PreviewPanelPlaceholder()
            }
        }
        .navigationTitle(siteViewModel.site?.displayName ?? "Victor")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
            }

            if siteViewModel.isLoading {
                ToolbarItem {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
        }
        .alert("Error", isPresented: .constant(siteViewModel.errorMessage != nil)) {
            Button("OK") {
                siteViewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = siteViewModel.errorMessage {
                Text(errorMessage)
            }
        }
    }

    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
}

// MARK: - Editor Panel (Phase 2: Editable)

struct EditorPanelView: View {
    let contentFile: ContentFile
    let fileNode: FileNode
    @Bindable var siteViewModel: SiteViewModel

    @State private var editableContent: String
    @State private var isSaving = false
    @State private var showSavedIndicator = false
    @State private var editorCoordinator: EditorTextView.Coordinator?
    @State private var isFrontmatterExpanded = false
    @State private var showConflictAlert = false

    init(contentFile: ContentFile, fileNode: FileNode, siteViewModel: SiteViewModel) {
        self.contentFile = contentFile
        self.fileNode = fileNode
        self.siteViewModel = siteViewModel
        // Initialize editable content with file's markdown
        _editableContent = State(initialValue: contentFile.markdownContent)
    }

    var hasUnsavedChanges: Bool {
        editableContent != contentFile.markdownContent
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            EditorToolbar(
                isLivePreviewEnabled: $siteViewModel.isLivePreviewEnabled,
                isSaving: isSaving,
                showSavedIndicator: showSavedIndicator,
                hasUnsavedChanges: hasUnsavedChanges,
                onSave: { Task { await saveFile() } },
                onFormat: { format in
                    editorCoordinator?.applyFormat(format)
                }
            )

            // Markdown Editor (takes priority)
            EditorTextView(text: $editableContent) { coordinator in
                editorCoordinator = coordinator
            }

            // Bottom Frontmatter Panel (collapsible)
            if contentFile.frontmatter != nil {
                Divider()

                FrontmatterBottomPanel(
                    frontmatter: contentFile.frontmatter!,
                    isExpanded: $isFrontmatterExpanded
                )
            }
        }
        .navigationTitle(contentFile.frontmatter?.title ?? "No title")
        .navigationSubtitle(hasUnsavedChanges ? "\(contentFile.fileName) • Edited" : (contentFile.fileName))
        // Update content when file changes
        .onChange(of: contentFile.markdownContent) { _, newValue in
            editableContent = newValue
        }
        // Sync editing content to view model for live preview (only if enabled)
        // Also trigger auto-save when content changes (if enabled)
        .onChange(of: editableContent) { _, newValue in
            if siteViewModel.isLivePreviewEnabled {
                siteViewModel.currentEditingContent = newValue
            }

            // Schedule auto-save (debounced 2 seconds) if auto-save is enabled
            if hasUnsavedChanges && siteViewModel.isAutoSaveEnabled {
                scheduleAutoSave()
            }
        }
        .alert("File Modified Externally", isPresented: $showConflictAlert) {
            Button("Reload from Disk") {
                Task {
                    await siteViewModel.reloadFile(node: fileNode)
                }
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("This file was modified by another application. Auto-save has been cancelled. You can reload the file to see external changes, or keep editing to manually save your version.")
        }
    }

    private func saveFile() async {
        isSaving = true
        showSavedIndicator = false

        // Combine frontmatter and markdown content
        let fullContent: String
        if let frontmatter = contentFile.frontmatter {
            let serialized = FrontmatterParser.shared.serializeFrontmatter(frontmatter)
            fullContent = serialized + "\n" + editableContent
        } else {
            fullContent = editableContent
        }

        let success = await siteViewModel.saveFile(node: fileNode, content: fullContent)

        isSaving = false

        if success {
            // Update the content file's markdown content
            contentFile.markdownContent = editableContent

            // Show saved indicator briefly
            showSavedIndicator = true
            try? await Task.sleep(for: .seconds(2))
            showSavedIndicator = false
        }
    }

    private func scheduleAutoSave() {
        // Prepare full content
        let fullContent: String
        if let frontmatter = contentFile.frontmatter {
            let serialized = FrontmatterParser.shared.serializeFrontmatter(frontmatter)
            fullContent = serialized + "\n" + editableContent
        } else {
            fullContent = editableContent
        }

        // Schedule auto-save with conflict detection
        Task {
            await AutoSaveService.shared.scheduleAutoSave(
                fileURL: fileNode.url,
                content: fullContent,
                lastModified: contentFile.lastModified,
                onConflict: { @MainActor in
                    // Cancel auto-save and show alert
                    showConflictAlert = true
                    return .cancel
                },
                onSuccess: { @MainActor newModificationDate in
                    // Update modification date
                    contentFile.lastModified = newModificationDate
                    contentFile.markdownContent = editableContent

                    // Show saved indicator briefly
                    showSavedIndicator = true
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        showSavedIndicator = false
                    }
                },
                onError: { @MainActor error in
                    // Show error in site view model (unless it's a user cancellation)
                    if !(error is AutoSaveError) {
                        siteViewModel.errorMessage = error.localizedDescription
                    }
                }
            )
        }
    }
}

// MARK: - Editor Toolbar

struct EditorToolbar: View {
    @Binding var isLivePreviewEnabled: Bool
    let isSaving: Bool
    let showSavedIndicator: Bool
    let hasUnsavedChanges: Bool
    let onSave: () -> Void
    let onFormat: (MarkdownFormat) -> Void

    var body: some View {
        HStack(spacing: 12) {
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

            Divider()
                .frame(height: 20)

            // Markdown Formatting Buttons
            HStack(spacing: 6) {
                Button(action: { onFormat(.bold) }) {
                    Label("Bold", systemImage: "bold")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Bold (⌘B)")

                Button(action: { onFormat(.italic) }) {
                    Label("Italic", systemImage: "italic")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Italic (⌘I)")

                Button(action: { onFormat(.heading) }) {
                    Label("Heading", systemImage: "textformat.size")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Heading")

                Button(action: { onFormat(.unorderedList) }) {
                    Label("Unordered List", systemImage: "list.bullet")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Unordered List")

                Button(action: { onFormat(.orderedList) }) {
                    Label("Ordered List", systemImage: "list.number")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Ordered List")
                
                Button(action: { onFormat(.code) }) {
                    Label("Code", systemImage: "text.word.spacing")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Code Block")
            }

            Spacer()

            // Save Button
            if showSavedIndicator {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else if isSaving {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 20, height: 20)
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

// MARK: - Preview Panel

struct PreviewPanel: View {
    let contentFile: ContentFile
    @Bindable var siteViewModel: SiteViewModel

    @State private var renderedHTML: String = ""
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        PreviewWebView(html: renderedHTML)
            .navigationTitle("Preview")
            .navigationSubtitle(contentFile.fileName)
            .onAppear {
                // Initial render
                updatePreview(content: siteViewModel.currentEditingContent.isEmpty ? contentFile.markdownContent : siteViewModel.currentEditingContent)
            }
            .onChange(of: siteViewModel.currentEditingContent) { _, newContent in
                // Debounce preview updates (300ms after typing stops)
                debounceTask?.cancel()
                debounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    if !Task.isCancelled {
                        updatePreview(content: newContent)
                    }
                }
            }
            .onChange(of: contentFile.id) { _, _ in
                // File changed, update immediately
                debounceTask?.cancel()
                updatePreview(content: siteViewModel.currentEditingContent.isEmpty ? contentFile.markdownContent : siteViewModel.currentEditingContent)
            }
    }

    private func updatePreview(content: String) {
        renderedHTML = MarkdownRenderer.shared.renderOrError(markdown: content)
    }
}

// MARK: - Frontmatter Bottom Panel

enum FrontmatterViewMode {
    case form
    case raw
}

struct FrontmatterBottomPanel: View {
    @Bindable var frontmatter: Frontmatter
    @Binding var isExpanded: Bool
    @State private var viewMode: FrontmatterViewMode = .form
    @State private var rawText: String = ""
    @State private var parseError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Collapsible header
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)

                    Text("Frontmatter")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(frontmatterFormatBadge)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Spacer()

                    // View mode picker (only show when expanded)
                    if isExpanded {
                        Picker("View Mode", selection: $viewMode) {
                            Text("Form").tag(FrontmatterViewMode.form)
                            Text("Raw").tag(FrontmatterViewMode.raw)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                        .labelsHidden()
                    }

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            .help(isExpanded ? "Collapse frontmatter" : "Expand frontmatter")

            // Frontmatter content (when expanded)
            if isExpanded {
                Divider()

                if viewMode == .form {
                    // Form view
                    ScrollView {
                        FrontmatterEditorView(frontmatter: frontmatter)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 250)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                } else {
                    // Raw view
                    VStack(spacing: 0) {
                        if let parseError = parseError {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(parseError)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Dismiss") {
                                    self.parseError = nil
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.1))

                            Divider()
                        }

                        TextEditor(text: $rawText)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxHeight: parseError != nil ? 200 : 250)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .onAppear {
            // Initialize raw text when first loaded
            if rawText.isEmpty {
                rawText = FrontmatterParser.shared.serializeFrontmatter(frontmatter)
            }
        }
        .onChange(of: viewMode) { oldValue, newValue in
            if newValue == .raw {
                // Switching to raw view - serialize current frontmatter
                rawText = FrontmatterParser.shared.serializeFrontmatter(frontmatter)
                parseError = nil
            } else if newValue == .form && oldValue == .raw {
                // Switching to form view - parse raw text
                parseRawText()
            }
        }
        .onChange(of: isExpanded) { _, newValue in
            if newValue {
                // When expanding, ensure raw text is up to date
                rawText = FrontmatterParser.shared.serializeFrontmatter(frontmatter)
            }
        }
    }

    private var frontmatterFormatBadge: String {
        switch frontmatter.format {
        case .yaml: return "YAML"
        case .toml: return "TOML"
        case .json: return "JSON"
        }
    }

    private func parseRawText() {
        // Try to parse the edited raw text
        let parser = FrontmatterParser.shared
        let (parsedFrontmatter, _) = parser.parseContent(rawText)

        guard let parsedFrontmatter = parsedFrontmatter else {
            parseError = "Failed to parse frontmatter. Please check the syntax."
            return
        }

        // Update the frontmatter object with parsed values
        frontmatter.title = parsedFrontmatter.title
        frontmatter.date = parsedFrontmatter.date
        frontmatter.draft = parsedFrontmatter.draft
        frontmatter.tags = parsedFrontmatter.tags
        frontmatter.categories = parsedFrontmatter.categories
        frontmatter.description = parsedFrontmatter.description
        frontmatter.customFields = parsedFrontmatter.customFields

        // Clear any previous errors
        parseError = nil
    }
}

// MARK: - Preview Panel Placeholder

struct PreviewPanelPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Preview",
            systemImage: "eye",
            description: Text("Select a markdown file to see preview")
        )
    }
}

#Preview {
    ContentView(siteViewModel: SiteViewModel())
}
