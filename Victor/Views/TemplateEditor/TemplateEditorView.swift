import SwiftUI
import AppKit

/// Editor view for Hugo template files with syntax highlighting and metadata panel
struct TemplateEditorView: View {
    @Bindable var template: Template
    let onSave: () async -> Void

    @State private var showMetadataPanel = true
    @State private var isSaving = false
    @State private var showSavedIndicator = false
    @State private var errorMessage: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HSplitView {
            // Main editor area
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
            .frame(minWidth: 400)

            // Metadata panel (collapsible)
            if showMetadataPanel {
                TemplateMetadataPanel(template: template)
                    .frame(minWidth: 200, idealWidth: 280, maxWidth: 350)
            }
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

            // Toggle metadata panel
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showMetadataPanel.toggle()
                }
            } label: {
                Image(systemName: showMetadataPanel ? "sidebar.trailing" : "sidebar.trailing")
                    .symbolVariant(showMetadataPanel ? .none : .slash)
            }
            .help(showMetadataPanel ? "Hide Info Panel" : "Show Info Panel")

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

            // Apply Go template syntax highlighting
            applySyntaxColors(to: textStorage, text: text)
        }

        private func applySyntaxColors(to textStorage: NSTextStorage, text: String) {
            // Template delimiters {{ }}
            let delimiterColor = NSColor.systemPurple
            let delimiterPattern = #/\{\{|\}\}/#

            for match in text.matches(of: delimiterPattern) {
                let range = NSRange(match.range, in: text)
                textStorage.addAttribute(.foregroundColor, value: delimiterColor, range: range)
            }

            // Template keywords (if, else, end, range, with, define, block, template)
            let keywordColor = NSColor.systemBlue
            let keywords = ["if", "else", "end", "range", "with", "define", "block", "template", "partial", "return"]
            for keyword in keywords {
                let pattern = "\\{\\{\\s*(\(keyword))\\b|\\{\\{-?\\s*(\(keyword))\\b"
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
                    for match in matches {
                        // Color the keyword part (group 1 or 2)
                        if match.range(at: 1).location != NSNotFound {
                            textStorage.addAttribute(.foregroundColor, value: keywordColor, range: match.range(at: 1))
                        }
                        if match.range(at: 2).location != NSNotFound {
                            textStorage.addAttribute(.foregroundColor, value: keywordColor, range: match.range(at: 2))
                        }
                    }
                }
            }

            // Variables (starting with . or $)
            let variableColor = NSColor.systemTeal
            let variablePattern = #/(\.[A-Z][a-zA-Z0-9_.]*|\$[a-zA-Z_][a-zA-Z0-9_]*)/#

            for match in text.matches(of: variablePattern) {
                let range = NSRange(match.range, in: text)
                textStorage.addAttribute(.foregroundColor, value: variableColor, range: range)
            }

            // Strings inside templates
            let stringColor = NSColor.systemGreen
            let stringPattern = #/"[^"]*"/#

            for match in text.matches(of: stringPattern) {
                let range = NSRange(match.range, in: text)
                textStorage.addAttribute(.foregroundColor, value: stringColor, range: range)
            }

            // HTML comments
            let commentColor = NSColor.systemGray
            let commentPattern = #/<!--[\s\S]*?-->/#

            for match in text.matches(of: commentPattern) {
                let range = NSRange(match.range, in: text)
                textStorage.addAttribute(.foregroundColor, value: commentColor, range: range)
            }

            // Go template comments {{/* */}}
            let templateCommentPattern = #/\{\{/\*[\s\S]*?\*/\}\}/#

            for match in text.matches(of: templateCommentPattern) {
                let range = NSRange(match.range, in: text)
                textStorage.addAttribute(.foregroundColor, value: commentColor, range: range)
            }

            // HTML tags
            let tagColor = NSColor.systemOrange
            let tagPattern = #/<\/?[a-zA-Z][a-zA-Z0-9]*/#

            for match in text.matches(of: tagPattern) {
                let range = NSRange(match.range, in: text)
                textStorage.addAttribute(.foregroundColor, value: tagColor, range: range)
            }
        }
    }
}

// MARK: - Template Metadata Panel

/// Panel showing template metadata (blocks, partials, functions, variables)
struct TemplateMetadataPanel: View {
    let template: Template

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Template Info
                templateInfoSection

                Divider()

                // Blocks section
                if !template.metadata.blocks.isEmpty {
                    blocksSection
                    Divider()
                }

                // Partials section
                if !template.metadata.partials.isEmpty {
                    partialsSection
                    Divider()
                }

                // Functions section
                if !template.metadata.functions.isEmpty {
                    functionsSection
                    Divider()
                }

                // Variables section
                if !template.metadata.variables.isEmpty {
                    variablesSection
                }

                Spacer()
            }
            .padding()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Sections

    private var templateInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Template Info", systemImage: "info.circle")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                InfoRow(label: "Type", value: template.templateType.displayName)
                InfoRow(label: "Path", value: template.relativePath)

                if template.isThemeTemplate, let themeName = template.themeName {
                    InfoRow(label: "Theme", value: themeName)
                }

                if template.metadata.hasBaseTemplate {
                    InfoRow(label: "Extends", value: "Base template (baseof.html)")
                }

                if template.metadata.definesBlocks {
                    InfoRow(label: "Defines", value: "\(template.metadata.blocksDefinedCount) block(s)")
                }
            }
            .font(.caption)
        }
    }

    private var blocksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Blocks (\(template.metadata.blocks.count))", systemImage: "square.stack.3d.up")
                .font(.headline)

            ForEach(template.metadata.blocks) { block in
                HStack {
                    Image(systemName: block.isDefinition ? "square.and.pencil" : "square.dashed")
                        .foregroundStyle(block.isDefinition ? .blue : .orange)
                        .frame(width: 20)

                    Text(block.name)
                        .font(.system(.caption, design: .monospaced))

                    Spacer()

                    Text(":\(block.lineNumber)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var partialsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Partials (\(template.metadata.partials.count))", systemImage: "puzzlepiece")
                .font(.headline)

            ForEach(template.metadata.partials) { partial in
                HStack {
                    Image(systemName: "puzzlepiece")
                        .foregroundStyle(.teal)
                        .frame(width: 20)

                    Text(partial.shortName)
                        .font(.system(.caption, design: .monospaced))

                    Spacer()

                    Text(":\(partial.lineNumber)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var functionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Functions (\(template.metadata.functions.count))", systemImage: "function")
                .font(.headline)

            let topFunctions = Array(template.metadata.functions.prefix(10))
            ForEach(topFunctions) { function in
                HStack {
                    Text(function.name)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(function.isControlFlow ? .blue : .primary)

                    Spacer()

                    Text("×\(function.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if template.metadata.functions.count > 10 {
                Text("... and \(template.metadata.functions.count - 10) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var variablesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Variables (\(template.metadata.variables.count))", systemImage: "dollarsign.circle")
                .font(.headline)

            let topVariables = Array(template.metadata.variables.prefix(10))
            ForEach(topVariables) { variable in
                HStack {
                    Text(variable.name)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(variableColor(for: variable))

                    Spacer()

                    Text("×\(variable.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if template.metadata.variables.count > 10 {
                Text("... and \(template.metadata.variables.count - 10) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func variableColor(for variable: TemplateVariable) -> Color {
        switch variable.category {
        case .page: return .blue
        case .site: return .purple
        case .params: return .orange
        case .local: return .teal
        case .other: return .primary
        }
    }
}

// MARK: - Helper Views

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label + ":")
                .foregroundStyle(.secondary)
            Text(value)
        }
    }
}
