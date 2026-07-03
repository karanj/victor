import SwiftUI
import AppKit

/// NSTextView wrapper with syntax highlighting for YAML/JSON/TOML
struct SyntaxHighlightedTextView: NSViewRepresentable {
    @Binding var text: String
    let language: String
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

        // Update language if changed
        context.coordinator.language = language

        // Only update if text differs (avoid cursor jumping)
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            context.coordinator.applySyntaxHighlighting(to: textView)
            textView.selectedRanges = selectedRanges
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, language: language)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SyntaxHighlightedTextView
        var language: String
        private var highlightingTimer: Timer?

        init(_ parent: SyntaxHighlightedTextView, language: String) {
            self.parent = parent
            self.language = language
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

            // Apply highlighting using SyntaxHighlighter
            Task { @MainActor in
                SyntaxHighlighter.shared.applyHighlighting(to: textStorage, language: self.language, font: font)
            }
        }
    }
}
