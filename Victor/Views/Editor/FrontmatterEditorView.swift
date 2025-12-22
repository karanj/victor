import SwiftUI

/// View for editing Hugo frontmatter fields
struct FrontmatterEditorView: View {
    @Bindable var frontmatter: Frontmatter
    @State private var isExpanded: Bool = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                // Title
                FormFieldView(label: "Title") {
                    TextField("Post title", text: Binding(
                        get: { frontmatter.title ?? "" },
                        set: { frontmatter.title = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                // Date (Optional)
                FormFieldView(label: "Date") {
                    HStack {
                        Toggle("Include date", isOn: Binding(
                            get: { frontmatter.date != nil },
                            set: { isOn in
                                if isOn {
                                    frontmatter.date = Date()
                                } else {
                                    frontmatter.date = nil
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)

                        if frontmatter.date != nil {
                            DatePicker(
                                "",
                                selection: Binding(
                                    get: { frontmatter.date ?? Date() },
                                    set: { frontmatter.date = $0 }
                                ),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .labelsHidden()
                        }
                    }
                }

                // Draft Status
                FormFieldView(label: "Draft") {
                    Toggle("Mark as draft", isOn: Binding(
                        get: { frontmatter.draft ?? false },
                        set: { frontmatter.draft = $0 }
                    ))
                }

                // Description
                FormFieldView(label: "Description") {
                    TextEditor(text: Binding(
                        get: { frontmatter.description ?? "" },
                        set: { frontmatter.description = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(height: 60)
                    .font(.body)
                    .border(Color(nsColor: .separatorColor), width: 1)
                }

                // Tags
                FormFieldView(label: "Tags") {
                    TagInputView(tags: Binding(
                        get: { frontmatter.tags ?? [] },
                        set: { frontmatter.tags = $0.isEmpty ? nil : $0 }
                    ))
                }

                // Categories
                FormFieldView(label: "Categories") {
                    TagInputView(tags: Binding(
                        get: { frontmatter.categories ?? [] },
                        set: { frontmatter.categories = $0.isEmpty ? nil : $0 }
                    ))
                }

                // Custom fields (read-only display for now)
                if !frontmatter.customFields.isEmpty {
                    Divider()
                        .padding(.vertical, 4)

                    Text("Custom Fields")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(Array(frontmatter.customFields.keys.sorted()), id: \.self) { key in
                        HStack {
                            Text(key)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(describing: frontmatter.customFields[key] ?? ""))
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        } label: {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.blue)
                Text("Frontmatter")
                    .font(.headline)
                Spacer()
                Text(frontmatterFormatBadge)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var frontmatterFormatBadge: String {
        switch frontmatter.format {
        case .yaml: return "YAML"
        case .toml: return "TOML"
        case .json: return "JSON"
        }
    }
}

// MARK: - Form Field View

struct FormFieldView<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
    }
}

// MARK: - Tag Input View

struct TagInputView: View {
    @Binding var tags: [String]
    @State private var newTag: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Display existing tags
            if !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                        TagChip(
                            text: tag,
                            onDelete: { removeTag(at: index) }
                        )
                    }
                }
            }

            // Input for new tags
            HStack {
                TextField("Add tag (press Enter)", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit {
                        addTag()
                    }

                if !newTag.isEmpty {
                    Button(action: addTag) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        tags.append(trimmed)
        newTag = ""
    }

    private func removeTag(at index: Int) {
        tags.remove(at: index)
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let text: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    // Move to next line
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }

            self.size = CGSize(
                width: maxWidth,
                height: currentY + lineHeight
            )
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var sampleFrontmatter = Frontmatter(
        rawContent: """
        ---
        title: "Sample Blog Post"
        date: 2024-01-15T10:00:00Z
        draft: false
        tags: ["swift", "swiftui", "macos"]
        categories: ["development"]
        description: "A sample blog post demonstrating frontmatter editing"
        ---
        """,
        format: .yaml
    )

    sampleFrontmatter.title = "Sample Blog Post"
    sampleFrontmatter.date = Date()
    sampleFrontmatter.draft = false
    sampleFrontmatter.tags = ["swift", "swiftui", "macos"]
    sampleFrontmatter.categories = ["development"]
    sampleFrontmatter.description = "A sample blog post demonstrating frontmatter editing"

    return ScrollView {
        FrontmatterEditorView(frontmatter: sampleFrontmatter)
    }
    .frame(width: 400, height: 600)
}
