import SwiftUI

// MARK: - Frontmatter View Mode

enum FrontmatterViewMode {
    case form
    case raw
}

// MARK: - Frontmatter Bottom Panel

struct FrontmatterBottomPanel: View {
    @Bindable var frontmatter: Frontmatter
    @Binding var isExpanded: Bool
    @State private var viewMode: FrontmatterViewMode = .form
    @State private var rawText: String = ""
    @State private var parseError: String?

    /// Panel height - stored in AppStorage for persistence
    @AppStorage("frontmatterPanelHeight") private var panelHeight: Double = 300

    /// Minimum and maximum heights for the panel
    private let minHeight: CGFloat = 150
    private let maxHeight: CGFloat = 600

    var body: some View {
        VStack(spacing: 0) {
            // Resize handle (only when expanded)
            if isExpanded {
                resizeHandle
            }

            // Collapsible header
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)

                    Text("Frontmatter")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(frontmatterFormatBadge)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Spacer()

                    // View mode picker (only show when expanded)
                    if isExpanded {
                        Picker("View Mode", selection: $viewMode) {
                            Text("Form").tag(FrontmatterViewMode.form)
                            Text("Raw").tag(FrontmatterViewMode.raw)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                        .labelsHidden()
                    }

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            .help(isExpanded ? "Collapse frontmatter" : "Expand frontmatter")

            // Frontmatter content (when expanded)
            if isExpanded {
                Divider()

                if viewMode == .form {
                    // Form view - FrontmatterEditorView has its own ScrollView
                    FrontmatterEditorView(frontmatter: frontmatter)
                        .frame(height: panelHeight)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                } else {
                    // Raw view
                    VStack(spacing: 0) {
                        if let parseError = parseError {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
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
                            .background(Color.orange.opacity(0.1))

                            Divider()
                        }

                        TextEditor(text: $rawText)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                    }
                    .frame(height: panelHeight)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .onAppear {
            // Initialize raw text when first loaded
            if rawText.isEmpty {
                rawText = FrontmatterParser.shared.serializeFrontmatter(frontmatter)
            }
        }
        .onChange(of: viewMode) { oldValue, newValue in
            if newValue == .raw {
                // Switching to raw view - serialize current frontmatter
                rawText = FrontmatterParser.shared.serializeFrontmatter(frontmatter)
                parseError = nil
            } else if newValue == .form && oldValue == .raw {
                // Switching to form view - parse raw text
                parseRawText()
            }
        }
        .onChange(of: isExpanded) { _, newValue in
            if newValue {
                // When expanding, ensure raw text is up to date
                rawText = FrontmatterParser.shared.serializeFrontmatter(frontmatter)
            }
        }
    }

    // MARK: - Resize Handle

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .overlay(alignment: .center) {
                // Visible drag indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 36, height: 4)
                    .padding(.vertical, 3)
            }
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Dragging up increases height (negative translation)
                        let newHeight = panelHeight - value.translation.height
                        panelHeight = min(maxHeight, max(minHeight, newHeight))
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .help("Drag to resize panel")
    }

    private var frontmatterFormatBadge: String {
        switch frontmatter.format {
        case .yaml: return "YAML"
        case .toml: return "TOML"
        case .json: return "JSON"
        }
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
        frontmatter.draft = parsedFrontmatter.draft
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

        // Clear any previous errors
        parseError = nil
    }
}
