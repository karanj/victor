import SwiftUI
import AppKit

/// Panel for editing plain text files
struct TextEditorPanel: View {
    let textFile: TextFile
    /// FileNode.id backing `textFile` - see TextEditorViewModel.nodeID for why
    /// this (not textFile.id) is what dirty-state reporting keys on.
    let nodeID: UUID
    @Bindable var viewModel: TextEditorViewModel
    @Bindable var siteViewModel: SiteViewModel

    // Accessibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar - extracted subview so its per-keystroke reads
            // (hasUnsavedChanges etc.) invalidate only the toolbar, not this
            // body and the focused-value publish below (keystroke-lag fix, part 2).
            TextEditorToolbar(textFile: textFile, viewModel: viewModel)

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
        .onAppear {
            viewModel.siteViewModel = siteViewModel
            viewModel.loadFile(textFile, nodeID: nodeID)
        }
        .onChange(of: textFile.id) { _, _ in
            viewModel.siteViewModel = siteViewModel
            viewModel.loadFile(textFile, nodeID: nodeID)
        }
        // Publish this editor's actions to the menu bar (File > Save/Revert).
        // No Markdown formatting or shortcode picker for plain-text files.
        // Equatable by editorID + transition-guarded hasUnsavedChanges, for the
        // same per-keystroke menu-storm reasons as EditorPanelView's publish -
        // see EditorActions' doc comment (keystroke-lag fix, part 2).
        .focusedValue(\.editorActions, EditorActions(
            editorID: nodeID,
            formatting: nil,
            showShortcodePicker: nil,
            save: {
                await viewModel.save()
                return true
            },
            revert: {
                await viewModel.reloadFromDisk()
            },
            hasUnsavedChanges: {
                siteViewModel.isFileModified(nodeID)
            }
        ))
    }
}

/// Toolbar for the plain-text editor. Separate view (not a computed property of
/// TextEditorPanel) so its reads of per-keystroke viewModel state re-render only
/// this subtree (keystroke-lag fix, part 2).
private struct TextEditorToolbar: View {
    let textFile: TextFile
    @Bindable var viewModel: TextEditorViewModel

    // Accessibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            // File type icon and name
            Image(systemName: textFile.fileType.systemImage)
                .foregroundStyle(textFile.fileType.defaultColor)
                .accessibilityHidden(true)

            Text(textFile.url.lastPathComponent)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            // File type badge
            Text(textFile.fileType.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.2))
                .cornerRadius(4)

            // File status badges
            FileStatusBadgeView(
                hasUnsavedChanges: viewModel.hasUnsavedChanges,
                showSavedIndicator: viewModel.showSavedIndicator
            )

            Spacer()

            EditorErrorLabel(message: viewModel.errorMessage)

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
            // No .keyboardShortcut here - File > Save (Cmd+S) is the single owner,
            // routed through the focusedValue(\.editorActions) published above.
            .disabled(!viewModel.hasUnsavedChanges || viewModel.isSaving)
            .help("Save (⌘S)")
            .accessibilityLabel("Save")

            // Reload button
            Button {
                Task {
                    await viewModel.reloadFromDisk()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload from disk")
            .accessibilityLabel("Reload from Disk")

            Divider()
                .frame(height: 20)

            // Open in external editor
            Button {
                NSWorkspace.shared.open(textFile.url)
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .help("Open in default app")
            .accessibilityLabel("Open in Default App")

            // Reveal in Finder
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([textFile.url])
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")
            .accessibilityLabel("Reveal in Finder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.fast), value: viewModel.hasUnsavedChanges)
        .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.fast), value: viewModel.showSavedIndicator)
    }
}

// MARK: - Text Editor NSTextView Wrapper

/// NSTextView wrapper for text editing
struct TextEditorTextView: NSViewRepresentable {
    @Binding var text: String
    let fileType: FileType
    let onTextChange: () -> Void

    // Editor preferences
    private let settings = AppSettings.shared

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
        textView.font = NSFont.monospacedSystemFont(ofSize: settings.editorFontSize, weight: .regular)
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

        // Set initial text and apply syntax highlighting
        textView.string = text
        context.coordinator.applySyntaxHighlighting(to: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Update font size if changed
        textView.font = NSFont.monospacedSystemFont(ofSize: settings.editorFontSize, weight: .regular)

        // Only update if text differs (avoid cursor jumping)
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            context.coordinator.applySyntaxHighlighting(to: textView)
            textView.selectedRanges = selectedRanges
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextEditorTextView
        private var highlightingTimer: Timer?

        init(_ parent: TextEditorTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onTextChange()

            // Debounce syntax highlighting
            highlightingTimer?.invalidate()
            highlightingTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                // Timer's closure type isn't statically MainActor-isolated even
                // though this Coordinator is - wrap the MainActor call explicitly
                // (WP3.5 Cluster 11).
                Task { @MainActor in
                    self?.applySyntaxHighlighting(to: textView)
                }
            }
        }

        func applySyntaxHighlighting(to textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }

            let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            let fileType = parent.fileType

            // Apply highlighting using SyntaxHighlighter (MainActor-isolated)
            Task { @MainActor in
                // Check if we have a language mapping for this file type
                guard let language = SyntaxHighlighter.shared.languageName(for: fileType) else {
                    // No highlighting for this type - just use default text color
                    return
                }
                SyntaxHighlighter.shared.applyHighlighting(to: textStorage, language: language, font: font)
            }
        }
    }
}
