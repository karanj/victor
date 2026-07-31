import SwiftUI
import AppKit

/// Editor view for Hugo template files with syntax highlighting
struct TemplateEditorView: View {
    @Bindable var template: Template
    let onSave: () async -> Void

    @State private var isSaving = false
    @State private var showSavedIndicator = false
    @State private var errorMessage: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            templateToolbar

            Divider()

            TemplateTextView(
                text: $template.content,
                onTextChange: {
                    // Content changed - handled by Template's hasUnsavedChanges
                }
            )
        }
    }

    // MARK: - Toolbar

    private var templateToolbar: some View {
        HStack {
            // Template type icon and name
            Image(systemName: template.templateType.systemImage)
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            Text(template.fileName)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            // Template type badge
            Text(template.templateType.displayName)
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(templateTypeBadgeColor)
                .cornerRadius(4)

            // Theme badge if applicable
            if template.isThemeTemplate, let themeName = template.themeName {
                Text(themeName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.2))
                    .cornerRadius(4)
            }

            // File status badges
            FileStatusBadgeView(
                hasUnsavedChanges: template.hasUnsavedChanges,
                showSavedIndicator: showSavedIndicator
            )

            Spacer()

            EditorErrorLabel(message: errorMessage)

            EditorToolbarDivider()

            EditorSaveButton(
                isSaving: isSaving,
                hasUnsavedChanges: template.hasUnsavedChanges,
                action: save
            )

            EditorReloadButton(action: reloadFromDisk)

            EditorToolbarDivider()

            EditorOpenExternalButton(url: template.url)
            EditorRevealInFinderButton(url: template.url)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.fast), value: template.hasUnsavedChanges)
        .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.fast), value: showSavedIndicator)
    }

    private var templateTypeBadgeColor: Color {
        switch template.templateType {
        case .base: return .purple
        case .partial: return .teal
        case .shortcode: return .orange
        case .single, .list: return .blue
        case .home: return .green
        case .taxonomy, .section: return .indigo
        case .other: return .gray
        }
    }

    // MARK: - Actions

    private func save() async {
        let helper = EditorSaveHelper()
        await helper.performSave(
            operation: { try await TemplateParser.shared.save(template) },
            setIsSaving: { isSaving = $0 },
            setShowSavedIndicator: { showSavedIndicator = $0 },
            setErrorMessage: { errorMessage = $0 },
            afterSave: { await onSave() }
        )
    }

    private func reloadFromDisk() async {
        let helper = EditorReloadHelper()
        await helper.performReload(
            from: template.url,
            updateContent: { content in
                template.content = content
                template.originalContent = content
                template.metadata = TemplateParser.shared.extractMetadata(from: content)
            },
            setErrorMessage: { errorMessage = $0 },
            markAsSaved: { template.markAsSaved() }
        )
    }
}

// MARK: - Template Text View (NSTextView wrapper)

/// NSTextView wrapper with Go template syntax awareness
struct TemplateTextView: NSViewRepresentable {
    @Binding var text: String
    let onTextChange: () -> Void

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
            // Apply syntax highlighting and restore cursor position after it completes
            context.coordinator.applySyntaxHighlighting(to: textView, preservingSelection: selectedRanges)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TemplateTextView
        private var highlightingTimer: Timer?

        init(_ parent: TemplateTextView) {
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

        func applySyntaxHighlighting(to textView: NSTextView, preservingSelection selectedRanges: [NSValue]? = nil) {
            guard let textStorage = textView.textStorage else { return }

            let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

            // Use SyntaxHighlighter for Go template highlighting
            Task { @MainActor in
                SyntaxHighlighter.shared.applyGoTemplateHighlighting(to: textStorage, font: font)

                // Restore selection after highlighting completes (if provided)
                if let selectedRanges = selectedRanges {
                    textView.selectedRanges = selectedRanges
                }
            }
        }
    }
}
