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
            // Toolbar
            EditorToolbar(
                isLivePreviewEnabled: $siteViewModel.isLivePreviewEnabled,
                isSaving: viewModel.isSaving,
                showSavedIndicator: viewModel.showSavedIndicator,
                hasUnsavedChanges: viewModel.hasUnsavedChanges,
                onSave: { Task { await viewModel.save() } },
                onFormat: { format in
                    editorCoordinator?.applyFormat(format)
                }
            )

            // Markdown Editor (takes priority)
            EditorTextView(text: $viewModel.editableContent) { coordinator in
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
        .navigationTitle(viewModel.navigationTitle)
        .navigationSubtitle(viewModel.navigationSubtitle)
        // Provide formatting function to focused value system for keyboard shortcuts
        .focusedValue(\.editorFormatting) { format in
            editorCoordinator?.applyFormat(format)
        }
        // When the selected file changes, reset the editor view model so it
        // points at the new file node and content instead of the previous one.
        .onChange(of: contentFile.id) { _, _ in
            viewModel = EditorViewModel(
                fileNode: fileNode,
                contentFile: contentFile,
                siteViewModel: siteViewModel
            )
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

                Button(action: { onFormat(.link) }) {
                    Label("Link", systemImage: "link")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Insert Link (⌘K)")

                Button(action: { onFormat(.image) }) {
                    Label("Image", systemImage: "photo")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Insert Image (⌘⇧I)")

                Button(action: { onFormat(.blockquote) }) {
                    Label("Quote", systemImage: "quote.opening")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Block Quote (⌘')")
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
