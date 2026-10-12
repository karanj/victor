import SwiftUI

// MARK: - Frontmatter Pane

/// What the expanded panel shows: one form category, or the raw text. A single
/// picker covers both, so Raw is just the last segment rather than a second control.
enum FrontmatterPane: Hashable, CaseIterable {
    case form(FrontmatterTab)
    case raw

    static var allCases: [FrontmatterPane] {
        FrontmatterTab.allCases.map { .form($0) } + [.raw]
    }

    /// What has to happen to the raw text when switching panes.
    enum Sync: Equatable {
        case none
        /// Rebuild raw text from the form's current values.
        case serialize
        /// Push edited raw text back into the form.
        case parse
    }

    func sync(to next: FrontmatterPane) -> Sync {
        switch (self, next) {
        case (.form, .raw): return .serialize
        case (.raw, .form): return .parse
        default: return .none
        }
    }

    var title: String {
        switch self {
        case .form(let tab): return tab.rawValue
        case .raw: return "Raw"
        }
    }

    var systemImage: String {
        switch self {
        case .form(let tab): return tab.icon
        case .raw: return "doc.plaintext"
        }
    }
}

// MARK: - Frontmatter Bottom Panel

/// Collapsible frontmatter editor under the markdown editor. Styled like the
/// formatting toolbar above it: plain window-background row, controls in glass
/// capsules, hairline separators only.
struct FrontmatterBottomPanel: View {
    @Bindable var frontmatter: Frontmatter
    @Binding var isExpanded: Bool
    @State private var pane: FrontmatterPane = .form(.essential)
    @State private var rawText: String = ""
    @State private var parseError: String?
    @State private var dragStartHeight: Double?

    /// Panel height - persisted via AppSettings
    @Bindable private var settings = AppSettings.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Minimum and maximum heights for the panel
    private let minHeight: CGFloat = 150
    private let maxHeight: CGFloat = 600

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                Divider()
                content
                    .frame(height: settings.frontmatterPanelHeight)
                    .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .overlay(alignment: .top) {
            Divider()
            if isExpanded {
                resizeHandle
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.standard), value: isExpanded)
        .onAppear {
            // Initialize raw text when first loaded
            if rawText.isEmpty {
                rawText = FrontmatterParser.shared.serializeFrontmatter(frontmatter)
            }
        }
        .onChange(of: pane) { oldValue, newValue in
            switch oldValue.sync(to: newValue) {
            case .serialize:
                rawText = FrontmatterParser.shared.serializeFrontmatter(frontmatter)
                parseError = nil
            case .parse:
                parseRawText()
            case .none:
                break
            }
        }
        .onChange(of: isExpanded) { _, newValue in
            if newValue {
                // When expanding, ensure raw text is up to date
                rawText = FrontmatterParser.shared.serializeFrontmatter(frontmatter)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)

                    Text("Frontmatter")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(frontmatter.format.displayName)
                        .secondaryBadgeStyle(font: .caption2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse frontmatter" : "Expand frontmatter")
            .accessibilityLabel("Frontmatter, \(frontmatter.format.displayName)")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            Spacer(minLength: 8)

            // Always laid out so the row height doesn't jump on expand/collapse.
            panePicker
                .opacity(isExpanded ? 1 : 0)
                .disabled(!isExpanded)
                .accessibilityHidden(!isExpanded)
        }
        .padding(.horizontal, AppConstants.Toolbar.horizontalPadding)
        .padding(.vertical, AppConstants.Toolbar.verticalPadding)
    }

    private var panePicker: some View {
        ViewThatFits(in: .horizontal) {
            paneGroups(iconOnly: false)
            paneGroups(iconOnly: true)
        }
    }

    private func paneGroups(iconOnly: Bool) -> some View {
        GlassEffectContainer(spacing: AppConstants.Toolbar.glassGroupSpacing) {
            HStack(spacing: AppConstants.Toolbar.glassGroupSpacing) {
                ToolbarGroup {
                    ForEach(FrontmatterTab.allCases, id: \.self) { tab in
                        paneButton(.form(tab), iconOnly: iconOnly)
                    }
                }
                ToolbarGroup {
                    paneButton(.raw, iconOnly: iconOnly)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Frontmatter view")
    }

    private func paneButton(_ option: FrontmatterPane, iconOnly: Bool) -> some View {
        let isSelected = pane == option
        return Button(action: { pane = option }) {
            Label(option.title, systemImage: option.systemImage)
                .labelStyle(.adaptive(iconOnly: iconOnly))
                .padding(.horizontal, 8)
                .frame(minHeight: AppConstants.Toolbar.iconButtonSize)
                .background(isSelected ? Color.primary.opacity(0.12) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .foregroundStyle(isSelected ? .primary : .secondary)
        .help(option.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch pane {
        case .form(let tab):
            // FrontmatterEditorView has its own ScrollView
            FrontmatterEditorView(frontmatter: frontmatter, selectedTab: tab)
        case .raw:
            rawEditor
        }
    }

    private var rawEditor: some View {
        VStack(spacing: 0) {
            if let parseError = parseError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.Status.warning)
                        .accessibilityHidden(true)
                    Text(parseError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") {
                        self.parseError = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
                .padding(8)
                .background(Color.Status.warning.opacity(0.1))

                Divider()
            }

            TextEditor(text: $rawText)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .accessibilityLabel(parseError.map { "Raw frontmatter, error: \($0)" } ?? "Raw frontmatter")
        }
    }

    // MARK: - Resize Handle

    /// Invisible grab strip straddling the panel's top hairline, like a split view divider.
    private var resizeHandle: some View {
        Color.clear
            .frame(height: 8)
            .contentShape(Rectangle())
            .offset(y: -4)
            .pointerStyle(.rowResize)
            .gesture(
                // Global space: the handle moves as the panel grows, so local
                // translations would feed back into themselves.
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStartHeight ?? settings.frontmatterPanelHeight
                        dragStartHeight = start
                        // Dragging up increases height (negative translation)
                        settings.frontmatterPanelHeight = min(maxHeight, max(minHeight, start - value.translation.height))
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
            .help("Drag to resize panel")
    }

    private func parseRawText() {
        // Try to parse the edited raw text
        let parser = FrontmatterParser.shared
        let (parsedFrontmatter, _) = parser.parseContent(rawText)

        guard let parsedFrontmatter = parsedFrontmatter else {
            parseError = "Failed to parse frontmatter. Please check the syntax."
            return
        }

        // Update the frontmatter object with parsed values
        // Essential fields
        frontmatter.title = parsedFrontmatter.title
        frontmatter.date = parsedFrontmatter.date
        frontmatter.isDraft = parsedFrontmatter.isDraft
        frontmatter.tags = parsedFrontmatter.tags
        frontmatter.categories = parsedFrontmatter.categories
        frontmatter.description = parsedFrontmatter.description

        // Publishing fields
        frontmatter.publishDate = parsedFrontmatter.publishDate
        frontmatter.expiryDate = parsedFrontmatter.expiryDate
        frontmatter.lastmod = parsedFrontmatter.lastmod
        frontmatter.weight = parsedFrontmatter.weight

        // URL fields
        frontmatter.slug = parsedFrontmatter.slug
        frontmatter.url = parsedFrontmatter.url
        frontmatter.aliases = parsedFrontmatter.aliases

        // SEO fields
        frontmatter.keywords = parsedFrontmatter.keywords
        frontmatter.summary = parsedFrontmatter.summary
        frontmatter.linkTitle = parsedFrontmatter.linkTitle

        // Layout fields
        frontmatter.type = parsedFrontmatter.type
        frontmatter.layout = parsedFrontmatter.layout

        // Flags
        frontmatter.headless = parsedFrontmatter.headless
        frontmatter.isCJKLanguage = parsedFrontmatter.isCJKLanguage
        frontmatter.markup = parsedFrontmatter.markup
        frontmatter.translationKey = parsedFrontmatter.translationKey

        // Complex fields
        frontmatter.menus = parsedFrontmatter.menus
        frontmatter.build = parsedFrontmatter.build
        frontmatter.sitemap = parsedFrontmatter.sitemap
        frontmatter.outputs = parsedFrontmatter.outputs
        frontmatter.resources = parsedFrontmatter.resources
        frontmatter.cascade = parsedFrontmatter.cascade
        frontmatter.params = parsedFrontmatter.params
        frontmatter.customFields = parsedFrontmatter.customFields

        // Mark as changed since we've updated from raw text
        frontmatter.markChanged()

        // Clear any previous errors
        parseError = nil
    }
}
