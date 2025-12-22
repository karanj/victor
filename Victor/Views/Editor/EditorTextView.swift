import SwiftUI
import AppKit

/// NSViewRepresentable wrapper around NSTextView for high-performance markdown editing
struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    var onCoordinatorReady: ((Coordinator) -> Void)?

    init(text: Binding<String>, onCoordinatorReady: ((Coordinator) -> Void)? = nil) {
        self._text = text
        self.onCoordinatorReady = onCoordinatorReady
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Create scroll view
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        // Create text view with proper frame
        let textView = NSTextView(frame: scrollView.bounds)

        // Store reference in coordinator
        context.coordinator.textView = textView

        // Configure text view for markdown editing
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor

        // Disable rich text features - we want plain text markdown
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = true

        // Disable smart quotes and dashes (important for code/markdown)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        // Configure text container for proper wrapping
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.autoresizingMask = [.width]

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        }

        // Set initial text
        textView.string = text

        // Set as document view
        scrollView.documentView = textView

        // Notify that coordinator is ready
        DispatchQueue.main.async {
            onCoordinatorReady?(context.coordinator)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Update text container width if scroll view size changed
        if let textContainer = textView.textContainer {
            let newWidth = scrollView.contentSize.width
            if textContainer.containerSize.width != newWidth {
                textContainer.containerSize = NSSize(width: newWidth, height: CGFloat.greatestFiniteMagnitude)
                textView.frame.size.width = newWidth
            }
        }

        // Only update if text has changed (avoid cursor jumping)
        if textView.string != text {
            // Save cursor position
            let selectedRange = textView.selectedRange()

            // Update text
            textView.string = text

            // Restore cursor position if still valid
            if selectedRange.location <= text.count {
                textView.setSelectedRange(selectedRange)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView
        weak var textView: NSTextView?

        init(_ parent: EditorTextView) {
            self.parent = parent
        }

        // Called whenever text changes
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            // Update binding
            parent.text = textView.string
        }

        // Apply markdown formatting
        func applyFormat(_ format: MarkdownFormat) {
            textView?.applyMarkdownFormat(format)
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var sampleText = """
    # Sample Markdown

    This is a **bold** and *italic* text.

    ## Code Example

    ```swift
    func hello() {
        print("Hello, World!")
    }
    ```

    - Item 1
    - Item 2
    - Item 3
    """

    return EditorTextView(text: $sampleText)
        .frame(width: 600, height: 400)
}

// MARK: - Markdown Formatting

enum MarkdownFormat {
    case bold
    case italic
    case heading
    case unorderedList
    case orderedList

    var prefix: String {
        switch self {
        case .heading: return "## "
        case .unorderedList: return "- "
        case .orderedList: return "1. "
        default: return ""
        }
    }

    var wrapper: (String, String)? {
        switch self {
        case .bold: return ("**", "**")
        case .italic: return ("*", "*")
        default: return nil
        }
    }
}

extension NSTextView {
    func applyMarkdownFormat(_ format: MarkdownFormat) {
        guard let textStorage = self.textStorage else { return }

        let selectedRange = self.selectedRange()
        let selectedText = selectedRange.length > 0
            ? (self.string as NSString).substring(with: selectedRange)
            : ""

        var newText = ""
        var newSelectionLocation = selectedRange.location
        var newSelectionLength = 0

        if let (prefix, suffix) = format.wrapper {
            // Wrap selected text or insert markers
            if !selectedText.isEmpty {
                newText = "\(prefix)\(selectedText)\(suffix)"
                newSelectionLocation = selectedRange.location
                newSelectionLength = newText.count
            } else {
                newText = "\(prefix)\(suffix)"
                newSelectionLocation = selectedRange.location + prefix.count
                newSelectionLength = 0
            }
        } else {
            // Insert prefix at line start
            let lineRange = (self.string as NSString).lineRange(for: selectedRange)
            let lineText = (self.string as NSString).substring(with: lineRange)

            if !selectedText.isEmpty {
                // Prefix each line
                let lines = lineText.components(separatedBy: .newlines)
                let prefixedLines = lines.map { line in
                    line.isEmpty ? line : "\(format.prefix)\(line)"
                }
                newText = prefixedLines.joined(separator: "\n")
                newSelectionLocation = lineRange.location
                newSelectionLength = newText.count
            } else {
                // Insert prefix at current line
                let lineStart = lineRange.location
                newText = lineText.replacingOccurrences(of: "^", with: format.prefix, options: .regularExpression)
                newSelectionLocation = lineStart + format.prefix.count
                newSelectionLength = 0

                // Replace entire line
                if self.shouldChangeText(in: lineRange, replacementString: newText) {
                    textStorage.replaceCharacters(in: lineRange, with: newText)
                    self.didChangeText()
                    self.setSelectedRange(NSRange(location: newSelectionLocation, length: newSelectionLength))
                    return
                }
            }
        }

        // Apply the change
        if self.shouldChangeText(in: selectedRange, replacementString: newText) {
            textStorage.replaceCharacters(in: selectedRange, with: newText)
            self.didChangeText()
            self.setSelectedRange(NSRange(location: newSelectionLocation, length: newSelectionLength))
        }
    }
}
