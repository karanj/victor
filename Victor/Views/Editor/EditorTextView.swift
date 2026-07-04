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

    /// Callback to show the shortcode picker (called from context menu)
    var onShowShortcodePicker: (() -> Void)?

    /// The file currently being edited and the site it belongs to - used only to
    /// decide where a dropped image should be copied (page bundle folder if this
    /// file lives in one, otherwise static/) and to validate the destination stays
    /// within the site. Nil in previews/tests where no site context exists.
    var fileNode: FileNode?
    var siteViewModel: SiteViewModel?

    /// Track if a redraw is already pending to avoid excessive needsDisplay calls
    private var redrawPending = false

    /// Schedule a coalesced redraw on the next run loop iteration
    /// This prevents multiple needsDisplay calls from causing redundant redraws
    private func scheduleRedrawIfNeeded() {
        guard highlightCurrentLine, !redrawPending else { return }
        redrawPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.redrawPending = false
            self.needsDisplay = true
        }
    }

    // MARK: - Drag and Drop

    override func awakeFromNib() {
        super.awakeFromNib()
        registerForDraggedTypes([.string, .fileURL])
    }

    /// Register for drag types when becoming first responder
    override func becomeFirstResponder() -> Bool {
        registerForDraggedTypes([.string, .fileURL])
        return super.becomeFirstResponder()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Accept string drops (markdown syntax from asset browser)
        if sender.draggingPasteboard.canReadObject(forClasses: [NSString.self], options: nil) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard

        // Try to get string first (markdown syntax from asset browser)
        if let strings = pasteboard.readObjects(forClasses: [NSString.self], options: nil) as? [String],
           let droppedString = strings.first {
            // Get drop location
            let dropPoint = convert(sender.draggingLocation, from: nil)

            // Find character index at drop point
            guard let layoutManager = layoutManager,
                  let textContainer = textContainer else {
                return false
            }

            let glyphIndex = layoutManager.glyphIndex(for: dropPoint, in: textContainer)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

            // Insert at drop location
            let insertRange = NSRange(location: min(charIndex, string.count), length: 0)

            if shouldChangeText(in: insertRange, replacementString: droppedString) {
                textStorage?.replaceCharacters(in: insertRange, with: droppedString)
                didChangeText()

                // Position cursor after inserted text
                let newPosition = insertRange.location + droppedString.count
                setSelectedRange(NSRange(location: newPosition, length: 0))
                return true
            }
        }

        // Try a dropped file (Finder, sidebar, or an asset dragged out then back in).
        // Images are copied into the site and turned into a markdown reference; every
        // other file type falls through to the default NSTextView behavior below
        // (inserts the raw file path), unchanged from before.
        //
        // `urlReadingFileURLsOnly` plus the explicit `isFileURL` check reject non-file
        // URLs (e.g. an https://.../photo.jpg dragged from a browser tab): without
        // both, a remote URL with an image-looking extension would be misread as a
        // local file and passed to FileSystemService.importFile, which would then
        // fail trying to copy a URL that isn't on disk. Non-file URLs fall through to
        // `super.performDragOperation`, matching pre-existing text-insertion behavior.
        if let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL],
           let droppedURL = fileURLs.first,
           droppedURL.isFileURL,
           FileType(url: droppedURL) == .image,
           let fileNode, let siteViewModel, let siteRoot = siteViewModel.site?.rootURL,
           let layoutManager = layoutManager, let textContainer = textContainer {

            let dropPoint = convert(sender.draggingLocation, from: nil)
            let glyphIndex = layoutManager.glyphIndex(for: dropPoint, in: textContainer)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

            let destination = ImageDropPathResolver.destination(
                currentFileParentURL: fileNode.parent?.url,
                parentIsPageBundle: fileNode.parent?.isPageBundle ?? false,
                siteRoot: siteRoot
            )

            do {
                let destURL = try FileSystemService.shared.importFile(
                    from: droppedURL, into: destination.directory, siteRoot: siteRoot
                )
                let markdown = ImageDropPathResolver.markdownImageReference(for: destURL, style: destination.style)

                // NSString length (UTF-16), not Swift's grapheme-cluster `.count` -
                // `charIndex` above is already a UTF-16 offset from the layout manager,
                // and mixing it with `.count` would misplace the cursor on any text
                // containing multi-scalar graphemes (victor-u16 is about not
                // introducing exactly this mismatch in new code).
                let nsLength = (string as NSString).length
                let insertRange = NSRange(location: min(charIndex, nsLength), length: 0)

                if shouldChangeText(in: insertRange, replacementString: markdown) {
                    textStorage?.replaceCharacters(in: insertRange, with: markdown)
                    didChangeText()
                    let newPosition = insertRange.location + (markdown as NSString).length
                    setSelectedRange(NSRange(location: newPosition, length: 0))
                }
                return true
            } catch {
                Logger.shared.error("Failed to import dropped image", error: error)
                siteViewModel.errorMessage = "Failed to import \(droppedURL.lastPathComponent): \(error.localizedDescription)"
                return false
            }
        }

        return super.performDragOperation(sender)
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

        insertMenu.addItem(NSMenuItem.separator())

        let shortcodeItem = NSMenuItem(title: "Hugo Shortcode…", action: #selector(insertShortcode), keyEquivalent: "K")
        shortcodeItem.keyEquivalentModifierMask = [.command, .shift]
        shortcodeItem.target = self
        insertMenu.addItem(shortcodeItem)

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

    @objc private func insertShortcode() {
        onShowShortcodePicker?()
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
        // Schedule coalesced redraw to update highlight position
        scheduleRedrawIfNeeded()
    }

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelectingFlag)
        // Schedule coalesced redraw to update highlight position
        // Skip during active selection (stillSelecting=true) to avoid constant redraws while dragging
        if !stillSelectingFlag {
            scheduleRedrawIfNeeded()
        }
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
    var fontName: String
    var onCoordinatorReady: ((Coordinator) -> Void)?
    var onCursorPositionChange: ((CursorPosition) -> Void)?
    var onShowShortcodePicker: (() -> Void)?
    /// File/site context for resolving where a dropped image should be copied.
    /// See `HighlightingTextView.fileNode`/`.siteViewModel`.
    var fileNode: FileNode?
    var siteViewModel: SiteViewModel?

    init(
        text: Binding<String>,
        highlightCurrentLine: Bool = true,
        fontSize: CGFloat = 13,
        fontName: String = "SF Mono",
        onCoordinatorReady: ((Coordinator) -> Void)? = nil,
        onCursorPositionChange: ((CursorPosition) -> Void)? = nil,
        onShowShortcodePicker: (() -> Void)? = nil,
        fileNode: FileNode? = nil,
        siteViewModel: SiteViewModel? = nil
    ) {
        self._text = text
        self.highlightCurrentLine = highlightCurrentLine
        self.fontSize = fontSize
        self.fontName = fontName
        self.onCoordinatorReady = onCoordinatorReady
        self.onCursorPositionChange = onCursorPositionChange
        self.onShowShortcodePicker = onShowShortcodePicker
        self.fileNode = fileNode
        self.siteViewModel = siteViewModel
    }

    /// Get the appropriate NSFont based on font name
    private func getFont(size: CGFloat) -> NSFont {
        if fontName == "SF Mono" {
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        } else if let font = NSFont(name: fontName, size: size) {
            return font
        } else {
            // Fallback to system monospace
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        }
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
        textView.onShowShortcodePicker = onShowShortcodePicker
        textView.fileNode = fileNode
        textView.siteViewModel = siteViewModel

        // Store reference in coordinator
        context.coordinator.textView = textView

        // Configure text view for markdown editing
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = getFont(size: fontSize)
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

        // Enable drag-and-drop for asset insertion
        textView.registerForDraggedTypes([.string, .fileURL])

        // Configure text container for proper wrapping
        // Horizontal padding provides breathing room from scrollbar/resize gutter
        textView.textContainerInset = NSSize(
            width: AppConstants.Editor.textContainerInsetWidth,
            height: AppConstants.Editor.textContainerInsetHeight
        )
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

        // Force initial layout after the view is set up
        // This ensures text is visible immediately without needing to click
        DispatchQueue.main.async {
            if let layoutManager = textView.layoutManager,
               let textContainer = textView.textContainer {
                layoutManager.ensureLayout(for: textContainer)
            }
            textView.needsDisplay = true
        }

        // Notify coordinator is ready and request focus after view is in hierarchy
        // Use RunLoop to ensure we're outside any layout pass
        RunLoop.main.perform {
            onCoordinatorReady?(context.coordinator)
            // Request focus so user can start typing immediately
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? HighlightingTextView else { return }

        // Update line highlighting preference
        if textView.highlightCurrentLine != highlightCurrentLine {
            textView.highlightCurrentLine = highlightCurrentLine
        }

        // Keep file/site context current (e.g. after switching files, EditorPanelView
        // re-creates this view with a new fileNode/siteViewModel pair)
        textView.fileNode = fileNode
        textView.siteViewModel = siteViewModel

        // Update font if size or family changed
        let expectedFont = getFont(size: fontSize)
        if let currentFont = textView.font,
           currentFont.pointSize != fontSize || currentFont.fontName != expectedFont.fontName {
            textView.font = expectedFont
        }

        // Only update if text has changed (avoid cursor jumping)
        // Use count comparison first as a cheap early-out before expensive string comparison
        let currentString = textView.string
        if currentString.count != text.count || currentString != text {
            // Save cursor position
            let selectedRange = textView.selectedRange()

            // Update text
            textView.string = text

            // Note: Removed forced ensureLayout() call - it was causing performance issues.
            // The layout manager will automatically lay out text when needed for display.
            // The original workaround for text not appearing was fixed in makeNSView with
            // the DispatchQueue.main.async ensureLayout call on initial creation.

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

        /// Insert text at the current cursor position
        func insertText(_ text: String) {
            guard let textView = textView else { return }
            let selectedRange = textView.selectedRange()

            if textView.shouldChangeText(in: selectedRange, replacementString: text) {
                textView.textStorage?.replaceCharacters(in: selectedRange, with: text)
                textView.didChangeText()

                // Position cursor after inserted text
                let newPosition = selectedRange.location + text.count
                textView.setSelectedRange(NSRange(location: newPosition, length: 0))
            }
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
