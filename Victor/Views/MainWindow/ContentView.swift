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

            // Editor
            EditorTextView(text: $editableContent) { coordinator in
                editorCoordinator = coordinator
            }
        }
        .navigationTitle(contentFile.fileName)
        .navigationSubtitle(hasUnsavedChanges ? "\(contentFile.relativePath) • Edited" : contentFile.relativePath)
        // Update content when file changes
        .onChange(of: contentFile.markdownContent) { _, newValue in
            editableContent = newValue
        }
        // Sync editing content to view model for live preview (only if enabled)
        .onChange(of: editableContent) { _, newValue in
            if siteViewModel.isLivePreviewEnabled {
                siteViewModel.currentEditingContent = newValue
            }
        }
    }

    private func saveFile() async {
        isSaving = true
        showSavedIndicator = false

        let success = await siteViewModel.saveFile(node: fileNode, content: editableContent)

        isSaving = false

        if success {
            // Show saved indicator briefly
            showSavedIndicator = true
            try? await Task.sleep(for: .seconds(2))
            showSavedIndicator = false
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
