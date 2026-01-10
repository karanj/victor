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

            Text(template.fileName)
                .font(.headline)

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

            // Unsaved indicator
            if template.hasUnsavedChanges {
                Circle()
                    .fill(Color.Status.modified)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Unsaved changes")
                    .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
            }

            // Saved indicator
            if showSavedIndicator {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.Status.saved)
                    .accessibilityLabel("Saved")
                    .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
            }

            Spacer()

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Saving indicator
            if isSaving {
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
                    await save()
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!template.hasUnsavedChanges || isSaving)
            .help("Save (⌘S)")

            // Reload button
            Button {
                Task {
                    await reloadFromDisk()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload from disk")

            Divider()
                .frame(height: 20)

            // Open in external editor
            Button {
                NSWorkspace.shared.open(template.url)
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .help("Open in default app")

            // Reveal in Finder
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([template.url])
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")
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
        isSaving = true
        errorMessage = nil

        do {
            try await TemplateParser.shared.save(template)
            await onSave()
            showSavedIndicator = true

            // Hide saved indicator after delay
            try? await Task.sleep(for: .seconds(2))
            showSavedIndicator = false
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }

        isSaving = false
    }

    private func reloadFromDisk() async {
        do {
            let content = try String(contentsOf: template.url, encoding: .utf8)
            template.content = content
            template.originalContent = content
            // Re-parse metadata
            template.metadata = TemplateParser.shared.extractMetadata(from: content)
        } catch {
            errorMessage = "Reload failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Template Text View (NSTextView wrapper)

/// NSTextView wrapper with Go template syntax awareness
struct TemplateTextView: NSViewRepresentable {
    @Binding var text: String
    let onTextChange: () -> Void

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
                self?.applySyntaxHighlighting(to: textView)
            }
        }

        func applySyntaxHighlighting(to textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }

            let fullRange = NSRange(location: 0, length: textStorage.length)
            let text = textView.string

            // Reset to default color
            let defaultColor = NSColor.textColor
            textStorage.addAttribute(.foregroundColor, value: defaultColor, range: fullRange)

            // Apply syntax highlighting
            applySyntaxColors(to: textStorage, text: text)
        }

        private func applySyntaxColors(to textStorage: NSTextStorage, text: String) {
            // Order matters - later patterns can override earlier ones

            // 1. HTML tags (opening and closing) - e.g., <div>, </div>, <img />, <br/>
            let tagColor = NSColor.systemOrange
            // Match full tags including attributes: <tagname ...> or </tagname>
            if let tagRegex = try? NSRegularExpression(pattern: "</?[a-zA-Z][a-zA-Z0-9]*(?:\\s+[^>]*)?>", options: []) {
                let matches = tagRegex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
                for match in matches {
                    textStorage.addAttribute(.foregroundColor, value: tagColor, range: match.range)
                }
            }

            // 2. HTML comments <!-- -->
            let commentColor = NSColor.systemGray
            if let commentRegex = try? NSRegularExpression(pattern: "<!--[\\s\\S]*?-->", options: []) {
                let matches = commentRegex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
                for match in matches {
                    textStorage.addAttribute(.foregroundColor, value: commentColor, range: match.range)
                }
            }

            // 3. Go template blocks {{ ... }}
            let delimiterColor = NSColor.systemPurple
            if let templateRegex = try? NSRegularExpression(pattern: "\\{\\{-?|\\-?\\}\\}", options: []) {
                let matches = templateRegex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
                for match in matches {
                    textStorage.addAttribute(.foregroundColor, value: delimiterColor, range: match.range)
                }
            }

            // 4. Go template comments {{/* */}}
            if let templateCommentRegex = try? NSRegularExpression(pattern: "\\{\\{/\\*[\\s\\S]*?\\*/\\}\\}", options: []) {
                let matches = templateCommentRegex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
                for match in matches {
                    textStorage.addAttribute(.foregroundColor, value: commentColor, range: match.range)
                }
            }

            // 5. Template keywords after {{ or {{-
            let keywordColor = NSColor.systemBlue
            let keywords = ["if", "else", "end", "range", "with", "define", "block", "template", "partial", "return"]
            for keyword in keywords {
                let pattern = "\\{\\{-?\\s*(\(keyword))\\b"
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
                    for match in matches {
                        if match.range(at: 1).location != NSNotFound {
                            textStorage.addAttribute(.foregroundColor, value: keywordColor, range: match.range(at: 1))
                        }
                    }
                }
            }

            // 6. Variables (starting with . or $) - e.g., .Title, .Params.author, $myVar
            let variableColor = NSColor.systemTeal
            if let varRegex = try? NSRegularExpression(pattern: "\\.[A-Z][a-zA-Z0-9_.]*|\\$[a-zA-Z_][a-zA-Z0-9_]*", options: []) {
                let matches = varRegex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
                for match in matches {
                    textStorage.addAttribute(.foregroundColor, value: variableColor, range: match.range)
                }
            }

            // 7. Strings in double quotes
            let stringColor = NSColor.systemGreen
            if let stringRegex = try? NSRegularExpression(pattern: "\"[^\"]*\"", options: []) {
                let matches = stringRegex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
                for match in matches {
                    textStorage.addAttribute(.foregroundColor, value: stringColor, range: match.range)
                }
            }
        }
    }
}
