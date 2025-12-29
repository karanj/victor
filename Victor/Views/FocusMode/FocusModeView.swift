import SwiftUI

/// Distraction-free writing mode with centered editor
struct FocusModeView: View {
    @Binding var text: String
    @Bindable var siteViewModel: SiteViewModel
    let fileName: String
    let contentFile: ContentFile

    /// Track scroll position for progress indicator
    @State private var scrollProgress: Double = 0

    /// Maximum comfortable reading/writing width
    private let maxEditorWidth: CGFloat = 700

    var body: some View {
        ZStack {
            // Dimmed background
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with file name and exit button (appears on hover)
                FocusModeTopBar(
                    fileName: fileName,
                    onExit: { siteViewModel.exitFocusMode() }
                )

                // Centered editor
                GeometryReader { geometry in
                    ScrollView {
                        VStack {
                            FocusModeEditor(text: $text)
                                .frame(width: min(maxEditorWidth, geometry.size.width - 80))
                                .frame(minHeight: geometry.size.height - 100)
                        }
                        .frame(maxWidth: .infinity)
                        .background(GeometryReader { inner in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: inner.frame(in: .named("scroll")).minY
                            )
                        })
                    }
                    .coordinateSpace(name: "scroll")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                        // Calculate scroll progress (0 to 1)
                        let contentHeight = max(1, geometry.size.height * 2) // Estimate
                        scrollProgress = min(1, max(0, -offset / contentHeight))
                    }
                }

                // Bottom bar with progress and word count
                FocusModeBottomBar(
                    text: text,
                    progress: scrollProgress
                )
            }
        }
        .onExitCommand {
            // Escape key exits focus mode
            siteViewModel.exitFocusMode()
        }
        .onChange(of: text) { _, newValue in
            // Sync changes to the content file so EditorViewModel picks them up
            contentFile.markdownContent = newValue
        }
    }
}

// MARK: - Scroll Offset Preference Key

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Focus Mode Top Bar

struct FocusModeTopBar: View {
    let fileName: String
    let onExit: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            // File name
            Text(fileName)
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()

            // Exit button
            Button {
                onExit()
            } label: {
                Label("Exit Focus Mode", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Exit Focus Mode (Esc)")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
        .opacity(isHovering ? 1 : 0.3)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Focus Mode Bottom Bar

struct FocusModeBottomBar: View {
    let text: String
    let progress: Double

    private var wordCount: Int {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    private var characterCount: Int {
        text.count
    }

    var body: some View {
        HStack {
            // Word count
            Text("\(wordCount) words")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("•")
                .foregroundStyle(.tertiary)

            Text("\(characterCount) characters")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Progress indicator
            HStack(spacing: 6) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 60)

                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 35, alignment: .trailing)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
    }
}

// MARK: - Focus Mode Editor

/// Simplified text editor for focus mode
struct FocusModeEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView(frame: scrollView.bounds)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true

        // Larger, more comfortable font for focus mode
        textView.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false

        // Disable rich text
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = true

        // Disable smart quotes
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        // Configure for comfortable writing
        textView.textContainerInset = NSSize(width: 0, height: 40)
        textView.autoresizingMask = [.width]
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
            textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        }

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // Set initial text
        textView.string = text

        scrollView.documentView = textView

        // Store reference in coordinator
        context.coordinator.textView = textView

        // Focus the text view and ensure layout after view is in hierarchy
        DispatchQueue.main.async {
            // Re-apply text in case it changed during setup
            if textView.string != text {
                textView.string = text
            }
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            textView.needsLayout = true
            textView.needsDisplay = true
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            if selectedRange.location <= text.count {
                textView.setSelectedRange(selectedRange)
            }
            // Force layout after content change
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            textView.needsDisplay = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FocusModeEditor
        weak var textView: NSTextView?

        init(_ parent: FocusModeEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var sampleText = """
    # Focus Mode

    This is a distraction-free writing environment.

    Write your thoughts here without any distractions.
    The interface is minimal and centered for comfortable reading and writing.

    Press Escape to exit focus mode.
    """

    let contentFile = ContentFile(
        url: URL(fileURLWithPath: "/sample.md"),
        markdownContent: sampleText
    )

    FocusModeView(
        text: $sampleText,
        siteViewModel: SiteViewModel(),
        fileName: "sample-post.md",
        contentFile: contentFile
    )
}
