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

    var body: some View {
        VStack(spacing: 0) {
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
                    // Form view
                    ScrollView {
                        FrontmatterEditorView(frontmatter: frontmatter)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 250)
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
                            .frame(maxHeight: parseError != nil ? 200 : 250)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                    }
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
        frontmatter.title = parsedFrontmatter.title
        frontmatter.date = parsedFrontmatter.date
        frontmatter.draft = parsedFrontmatter.draft
        frontmatter.tags = parsedFrontmatter.tags
        frontmatter.categories = parsedFrontmatter.categories
        frontmatter.description = parsedFrontmatter.description
        frontmatter.customFields = parsedFrontmatter.customFields

        // Clear any previous errors
        parseError = nil
    }
}
