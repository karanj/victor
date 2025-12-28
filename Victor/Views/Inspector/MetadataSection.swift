import SwiftUI

/// Metadata section for the inspector panel
/// Wraps FrontmatterEditorView for editing frontmatter fields
struct MetadataSection: View {
    @Bindable var frontmatter: Frontmatter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title
            InspectorFieldView(label: "Title") {
                TextField("Post title", text: Binding(
                    get: { frontmatter.title ?? "" },
                    set: { frontmatter.title = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            }

            // Date
            InspectorFieldView(label: "Date") {
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { frontmatter.date != nil },
                        set: { isOn in
                            frontmatter.date = isOn ? Date() : nil
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                    if frontmatter.date != nil {
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { frontmatter.date ?? Date() },
                                set: { frontmatter.date = $0 }
                            ),
                            displayedComponents: [.date]
                        )
                        .labelsHidden()
                        .controlSize(.small)
                    } else {
                        Text("No date")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Draft status
            InspectorFieldView(label: "Status") {
                Toggle("Draft", isOn: Binding(
                    get: { frontmatter.draft ?? false },
                    set: { frontmatter.draft = $0 }
                ))
                .toggleStyle(.checkbox)
                .controlSize(.small)
            }

            // Description
            InspectorFieldView(label: "Description") {
                TextEditor(text: Binding(
                    get: { frontmatter.description ?? "" },
                    set: { frontmatter.description = $0.isEmpty ? nil : $0 }
                ))
                .frame(height: 50)
                .font(.caption)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .border(Color(nsColor: .separatorColor), width: 1)
            }

            // Tags
            InspectorFieldView(label: "Tags") {
                InspectorTagInput(tags: Binding(
                    get: { frontmatter.tags ?? [] },
                    set: { frontmatter.tags = $0.isEmpty ? nil : $0 }
                ))
            }

            // Categories
            InspectorFieldView(label: "Categories") {
                InspectorTagInput(tags: Binding(
                    get: { frontmatter.categories ?? [] },
                    set: { frontmatter.categories = $0.isEmpty ? nil : $0 }
                ))
            }

            // Custom fields (read-only)
            if !frontmatter.customFields.isEmpty {
                Divider()
                    .padding(.vertical, 4)

                Text("Custom Fields")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(Array(frontmatter.customFields.keys.sorted()), id: \.self) { key in
                    HStack {
                        Text(key)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(describing: frontmatter.customFields[key] ?? ""))
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - Inspector Field View

/// Compact form field for inspector panel
struct InspectorFieldView<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
    }
}

// MARK: - Inspector Tag Input

/// Compact tag input for inspector panel
struct InspectorTagInput: View {
    @Binding var tags: [String]
    @State private var newTag: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Existing tags
            if !tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                        InspectorTagChip(
                            text: tag,
                            onDelete: { tags.remove(at: index) }
                        )
                    }
                }
            }

            // Add new tag
            HStack(spacing: 4) {
                TextField("Add...", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .onSubmit {
                        addTag()
                    }

                if !newTag.isEmpty {
                    Button(action: addTag) {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption)
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
}

// MARK: - Inspector Tag Chip

/// Compact tag chip for inspector panel
struct InspectorTagChip: View {
    let text: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Text(text)
                .font(.caption2)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var frontmatter = Frontmatter(rawContent: "", format: .yaml)

    ScrollView {
        MetadataSection(frontmatter: frontmatter)
            .padding()
    }
    .frame(width: 260, height: 500)
}
