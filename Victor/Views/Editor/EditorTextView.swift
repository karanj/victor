import SwiftUI
import AppKit

// MARK: - Custom Text View with Line Highlighting

/// Custom NSTextView subclass that highlights the current line and provides custom context menu
final class HighlightingTextView: NSTextView {

    /// Whether to show current line highlighting
    var highlightCurrentLine: Bool = true {
        didSet {
            needsDisplay = true
        }
    }

    /// Color for the current line highlight
    private var highlightColor: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(0.08)
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()

        // Find the index to insert our items (after Cut/Copy/Paste)
        var insertIndex = 0
        for (index, item) in menu.items.enumerated() {
            if item.isSeparatorItem && index > 2 {
                insertIndex = index
                break
            }
        }
        if insertIndex == 0 {
            insertIndex = min(3, menu.items.count)
        }

        // Insert separator before our items
        menu.insertItem(NSMenuItem.separator(), at: insertIndex)
        insertIndex += 1

        // Text formatting submenu
        let formatMenu = NSMenu(title: "Format")

        let boldItem = NSMenuItem(title: "Bold", action: #selector(formatBold), keyEquivalent: "b")
        boldItem.keyEquivalentModifierMask = .command
        boldItem.target = self
        formatMenu.addItem(boldItem)

        let italicItem = NSMenuItem(title: "Italic", action: #selector(formatItalic), keyEquivalent: "i")
        italicItem.keyEquivalentModifierMask = .command
        italicItem.target = self
        formatMenu.addItem(italicItem)

        formatMenu.addItem(NSMenuItem.separator())

        // Heading submenu
        let headingMenu = NSMenu(title: "Heading")
        for level in 1...6 {
            let headingItem = NSMenuItem(title: "Heading \(level)", action: #selector(formatHeading(_:)), keyEquivalent: "")
            headingItem.tag = level
            headingItem.target = self
            headingMenu.addItem(headingItem)
        }
        let headingMenuItem = NSMenuItem(title: "Heading", action: nil, keyEquivalent: "")
        headingMenuItem.submenu = headingMenu
        formatMenu.addItem(headingMenuItem)

        let formatMenuItem = NSMenuItem(title: "Format", action: nil, keyEquivalent: "")
        formatMenuItem.submenu = formatMenu
        menu.insertItem(formatMenuItem, at: insertIndex)
        insertIndex += 1

        // Insert submenu
        let insertMenu = NSMenu(title: "Insert")

        let linkItem = NSMenuItem(title: "Link", action: #selector(insertLink), keyEquivalent: "k")
        linkItem.keyEquivalentModifierMask = .command
        linkItem.target = self
        insertMenu.addItem(linkItem)

        let imageItem = NSMenuItem(title: "Image", action: #selector(insertImage), keyEquivalent: "I")
        imageItem.keyEquivalentModifierMask = [.command, .shift]
        imageItem.target = self
        insertMenu.addItem(imageItem)

        insertMenu.addItem(NSMenuItem.separator())

        let codeItem = NSMenuItem(title: "Code Block", action: #selector(insertCodeBlock), keyEquivalent: "")
        codeItem.target = self
        insertMenu.addItem(codeItem)

        let quoteItem = NSMenuItem(title: "Block Quote", action: #selector(insertBlockQuote), keyEquivalent: "'")
        quoteItem.keyEquivalentModifierMask = .command
        quoteItem.target = self
        insertMenu.addItem(quoteItem)

        insertMenu.addItem(NSMenuItem.separator())

        let bulletItem = NSMenuItem(title: "Bullet List", action: #selector(insertBulletList), keyEquivalent: "")
        bulletItem.target = self
        insertMenu.addItem(bulletItem)

        let numberItem = NSMenuItem(title: "Numbered List", action: #selector(insertNumberedList), keyEquivalent: "")
        numberItem.target = self
        insertMenu.addItem(numberItem)

        let insertMenuItem = NSMenuItem(title: "Insert", action: nil, keyEquivalent: "")
        insertMenuItem.submenu = insertMenu
        menu.insertItem(insertMenuItem, at: insertIndex)

        return menu
    }

    // MARK: - Format Actions

    @objc private func formatBold() {
        applyMarkdownFormat(.bold)
    }

    @objc private func formatItalic() {
        applyMarkdownFormat(.italic)
    }

    @objc private func formatHeading(_ sender: NSMenuItem) {
        applyMarkdownFormat(.heading(level: sender.tag))
    }

    @objc private func insertLink() {
        applyMarkdownFormat(.link)
    }

    @objc private func insertImage() {
        applyMarkdownFormat(.image)
    }

    @objc private func insertCodeBlock() {
        applyMarkdownFormat(.code)
    }

    @objc private func insertBlockQuote() {
        applyMarkdownFormat(.blockquote)
    }

    @objc private func insertBulletList() {
        applyMarkdownFormat(.unorderedList)
    }

    @objc private func insertNumberedList() {
        applyMarkdownFormat(.orderedList)
    }

    // MARK: - Line Highlighting

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard highlightCurrentLine,
              let layoutManager = layoutManager,
              textContainer != nil else { return }

        // Get cursor position
        let cursorPosition = selectedRange().location

        // Handle empty document
        guard cursorPosition <= string.count else { return }

        // Get the glyph range for the cursor position
        let charRange = NSRange(location: min(cursorPosition, max(0, string.count - 1)), length: 0)

        // Handle empty string case
        if string.isEmpty {
            // Draw highlight for the first line when empty
            var lineRect = NSRect(x: 0, y: textContainerInset.height, width: bounds.width, height: 20)
            lineRect.origin.x = 0
            lineRect.size.width = bounds.width
            highlightColor.setFill()
            lineRect.fill()
            return
        }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)

        // Get the line fragment rect
        var lineRect = layoutManager.lineFragmentRect(forGlyphAt: max(0, glyphRange.location), effectiveRange: nil)

        // Adjust for text container inset
        lineRect.origin.y += textContainerInset.height
        lineRect.origin.x = 0
        lineRect.size.width = bounds.width

        // Draw the highlight
        highlightColor.setFill()
        lineRect.fill()
    }

    override func setSelectedRange(_ charRange: NSRange) {
        super.setSelectedRange(charRange)
        // Redraw to update highlight position
        needsDisplay = true
    }

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelectingFlag)
        // Redraw to update highlight position
        needsDisplay = true
    }
}

// MARK: - Editor Text View

/// Cursor position in the document
struct CursorPosition: Equatable {
    let line: Int
    let column: Int
}

/// NSViewRepresentable wrapper around NSTextView for high-performance markdown editing
struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    var highlightCurrentLine: Bool
    var fontSize: CGFloat
    var onCoordinatorReady: ((Coordinator) -> Void)?
    var onCursorPositionChange: ((CursorPosition) -> Void)?

    init(
        text: Binding<String>,
        highlightCurrentLine: Bool = true,
        fontSize: CGFloat = 13,
        onCoordinatorReady: ((Coordinator) -> Void)? = nil,
        onCursorPositionChange: ((CursorPosition) -> Void)? = nil
    ) {
        self._text = text
        self.highlightCurrentLine = highlightCurrentLine
        self.fontSize = fontSize
        self.onCoordinatorReady = onCoordinatorReady
        self.onCursorPositionChange = onCursorPositionChange
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Create scroll view
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        // Create text view with proper frame (using custom subclass for line highlighting)
        let textView = HighlightingTextView(frame: scrollView.bounds)
        textView.highlightCurrentLine = highlightCurrentLine

        // Store reference in coordinator
        context.coordinator.textView = textView

        // Configure text view for markdown editing
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
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
        // Horizontal padding provides breathing room from scrollbar/resize gutter
        textView.textContainerInset = NSSize(width: 16, height: 10)
        textView.autoresizingMask = [.width]
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
            // Set height to infinity for vertical scrolling, width will track text view
            textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        }

        // Set min/max size to allow vertical growth but constrain horizontal
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // Set initial text
        textView.string = text

        // Set as document view
        scrollView.documentView = textView

        // Force layout after view is in hierarchy to ensure proper text display
        DispatchQueue.main.async {
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            textView.needsLayout = true
            textView.needsDisplay = true
            scrollView.needsLayout = true
            onCoordinatorReady?(context.coordinator)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? HighlightingTextView else { return }

        // Update line highlighting preference
        if textView.highlightCurrentLine != highlightCurrentLine {
            textView.highlightCurrentLine = highlightCurrentLine
        }

        // Update font size if changed
        if let currentFont = textView.font, currentFont.pointSize != fontSize {
            textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
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
        weak var textView: HighlightingTextView?

        init(_ parent: EditorTextView) {
            self.parent = parent
        }

        deinit {
            textView?.delegate = nil
        }

        // Called whenever text changes
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            // Update binding
            parent.text = textView.string

            // Also update cursor position on text change
            updateCursorPosition()
        }

        // Called when selection changes (cursor movement)
        func textViewDidChangeSelection(_ notification: Notification) {
            updateCursorPosition()
        }

        // Calculate and report cursor position
        private func updateCursorPosition() {
            guard let textView = textView else { return }

            let text = textView.string
            let cursorLocation = textView.selectedRange().location

            // Calculate line and column
            let position = calculateLineAndColumn(text: text, cursorLocation: cursorLocation)
            parent.onCursorPositionChange?(position)
        }

        /// Calculate line number and column from cursor location
        private func calculateLineAndColumn(text: String, cursorLocation: Int) -> CursorPosition {
            guard !text.isEmpty, cursorLocation >= 0 else {
                return CursorPosition(line: 1, column: 1)
            }

            let nsString = text as NSString
            let safeLocation = min(cursorLocation, nsString.length)

            // Count newlines up to cursor position to get line number
            let textUpToCursor = nsString.substring(to: safeLocation)
            let lines = textUpToCursor.components(separatedBy: "\n")
            let lineNumber = lines.count

            // Column is the length of the last line + 1 (1-based)
            let column = (lines.last?.count ?? 0) + 1

            return CursorPosition(line: lineNumber, column: column)
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
    case heading(level: Int)
    case unorderedList
    case orderedList
    case code
    case link
    case image
    case blockquote

    var prefix: String {
        switch self {
        case .heading(let level):
            let clampedLevel = max(1, min(6, level))
            return String(repeating: "#", count: clampedLevel) + " "
        case .unorderedList: return "- "
        case .orderedList: return "1. "
        case .blockquote: return "> "
        default: return ""
        }
    }

    var wrapper: (String, String)? {
        switch self {
        case .bold: return ("**", "**")
        case .italic: return ("*", "*")
        case .code: return ("```\n","\n```")
        default: return nil
        }
    }

    var linkTemplate: (String, String, Int)? {
        switch self {
        case .link: return ("[", "](url)", 1) // cursor offset from start
        case .image: return ("![", "](url)", 2) // cursor offset from start
        default: return nil
        }
    }

    /// Whether this format is a link (used for placeholder text selection)
    var isLink: Bool {
        if case .link = self { return true }
        return false
    }

    /// Whether this format is a heading (used for replacement logic)
    var isHeading: Bool {
        if case .heading = self { return true }
        return false
    }
}

extension NSTextView {
    /// Replace existing heading markers (e.g., "## ") with new ones, or add if none exist
    static func replaceHeadingPrefix(in line: String, with newPrefix: String) -> String {
        // Pattern matches 1-6 # characters followed by a space at the start of the line
        let headingPattern = "^#{1,6} "

        if let range = line.range(of: headingPattern, options: .regularExpression) {
            // Replace existing heading markers
            return line.replacingCharacters(in: range, with: newPrefix)
        } else {
            // No existing heading, add the new prefix
            return line.isEmpty ? line : "\(newPrefix)\(line)"
        }
    }

    func applyMarkdownFormat(_ format: MarkdownFormat) {
        guard let textStorage = self.textStorage else { return }

        let selectedRange = self.selectedRange()
        let selectedText = selectedRange.length > 0
            ? (self.string as NSString).substring(with: selectedRange)
            : ""

        var newText = ""
        var newSelectionLocation = selectedRange.location
        var newSelectionLength = 0

        // Handle link and image templates
        if let (prefix, suffix, cursorOffset) = format.linkTemplate {
            if !selectedText.isEmpty {
                // Use selected text as link text/alt text
                newText = "\(prefix)\(selectedText)\(suffix)"
                // Select the URL placeholder
                newSelectionLocation = selectedRange.location + prefix.count + selectedText.count + 2 // after "]("
                newSelectionLength = 3 // select "url"
            } else {
                // Insert template with placeholders
                let placeholder = format.isLink ? "text" : "alt text"
                newText = "\(prefix)\(placeholder)\(suffix)"
                // Select the placeholder text
                newSelectionLocation = selectedRange.location + cursorOffset
                newSelectionLength = placeholder.count
            }
        } else if let (prefix, suffix) = format.wrapper {
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
                    if format.isHeading {
                        // Replace existing heading markers
                        return Self.replaceHeadingPrefix(in: line, with: format.prefix)
                    }
                    return line.isEmpty ? line : "\(format.prefix)\(line)"
                }
                newText = prefixedLines.joined(separator: "\n")
                newSelectionLocation = lineRange.location
                newSelectionLength = newText.count
            } else {
                // Insert/replace prefix at current line
                let lineStart = lineRange.location

                if format.isHeading {
                    // Replace existing heading markers or add new ones
                    newText = Self.replaceHeadingPrefix(in: lineText, with: format.prefix)
                } else {
                    newText = "\(format.prefix)\(lineText)"
                }

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
