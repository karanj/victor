import SwiftUI
import AppKit

/// Panel for editing plain text files
struct TextEditorPanel: View {
    let textFile: TextFile
    @Bindable var viewModel: TextEditorViewModel

    // Accessibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .onAppear {
            viewModel.loadFile(textFile)
        }
        .onChange(of: textFile.id) { _, _ in
            viewModel.loadFile(textFile)
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

            // File status badges
            FileStatusBadgeView(
                hasUnsavedChanges: viewModel.hasUnsavedChanges,
                showSavedIndicator: viewModel.showSavedIndicator
            )

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

            // Reveal in Finder
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([textFile.url])
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")
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
    @AppStorage("editorFontSize") private var editorFontSize: Double = 13.0

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
        textView.font = NSFont.monospacedSystemFont(ofSize: editorFontSize, weight: .regular)
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
        textView.font = NSFont.monospacedSystemFont(ofSize: editorFontSize, weight: .regular)

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
                self?.applySyntaxHighlighting(to: textView)
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
