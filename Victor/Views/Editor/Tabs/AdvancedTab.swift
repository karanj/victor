import SwiftUI

/// Advanced frontmatter fields tab (layout, build, outputs, resources, custom params)
struct AdvancedTab: View {
    @Bindable var frontmatter: Frontmatter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Layout Section
            SectionHeader("Layout", help: "Override the default template and content type")

            HStack(spacing: 16) {
                TextFieldWithCount(
                    label: "Type",
                    help: "Content type (defaults to section name)",
                    text: $frontmatter.type,
                    placeholder: "e.g., post, page"
                )

                TextFieldWithCount(
                    label: "Layout",
                    help: "Specific template to use for this page",
                    text: $frontmatter.layout,
                    placeholder: "e.g., single, list"
                )
            }

            // MARK: - Build Options Section
            SectionHeader("Build Options", help: "Control how Hugo builds and lists this page")

            buildOptionsSection

            // MARK: - Output Formats Section
            SectionHeader("Output Formats", help: "Which formats to generate for this page")

            outputFormatsSection

            // MARK: - Flags Section
            SectionHeader("Page Flags")

            flagsSection

            // MARK: - Custom Parameters Section
            SectionHeader("Custom Parameters", help: "Additional parameters accessible in templates via .Params")

            CustomFieldEditor(fields: $frontmatter.params)

            // MARK: - Other Custom Fields Section
            if !frontmatter.customFields.isEmpty {
                SectionHeader("Other Fields", help: "Unrecognized frontmatter fields")

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
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var buildOptionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                // List option
                FormFieldWithHelp(label: "List", help: "When to include in page lists") {
                    Picker("", selection: Binding(
                        get: { frontmatter.build?.list ?? .always },
                        set: {
                            ensureBuildExists()
                            frontmatter.build?.list = $0
                        }
                    )) {
                        ForEach(BuildOptions.ListOption.allCases, id: \.self) { option in
                            Text(option.rawValue.capitalized).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }

                // Render option
                FormFieldWithHelp(label: "Render", help: "When to render this page to disk") {
                    Picker("", selection: Binding(
                        get: { frontmatter.build?.render ?? .always },
                        set: {
                            ensureBuildExists()
                            frontmatter.build?.render = $0
                        }
                    )) {
                        ForEach(BuildOptions.RenderOption.allCases, id: \.self) { option in
                            Text(option.rawValue.capitalized).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }

            // Publish Resources
            FormFieldWithHelp(label: "Publish Resources", help: "Whether to publish page resources (images, etc.)") {
                Toggle("Publish page resources", isOn: Binding(
                    get: { frontmatter.build?.publishResources ?? true },
                    set: {
                        ensureBuildExists()
                        frontmatter.build?.publishResources = $0
                    }
                ))
            }
        }
    }

    private var outputFormatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: Binding(
                    get: { frontmatter.outputs != nil },
                    set: { isOn in
                        frontmatter.outputs = isOn ? ["html"] : nil
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()

                Text("Override default outputs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if frontmatter.outputs != nil {
                FlowLayout(spacing: 8) {
                    ForEach(OutputFormat.allCases, id: \.self) { format in
                        let isSelected = frontmatter.outputs?.contains(format.rawValue) ?? false
                        Toggle(format.displayName, isOn: Binding(
                            get: { isSelected },
                            set: { isOn in
                                toggleOutput(format.rawValue, isOn: isOn)
                            }
                        ))
                        .toggleStyle(.button)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var flagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Headless
            FormFieldWithHelp(label: "Headless", help: "Create headless bundle (resources without a page)") {
                Toggle("Headless bundle", isOn: Binding(
                    get: { frontmatter.headless ?? false },
                    set: { frontmatter.headless = $0 ? $0 : nil }
                ))
            }

            // CJK Language
            FormFieldWithHelp(label: "CJK Language", help: "Content uses CJK (affects word count)") {
                Toggle("CJK content", isOn: Binding(
                    get: { frontmatter.isCJKLanguage ?? false },
                    set: { frontmatter.isCJKLanguage = $0 ? $0 : nil }
                ))
            }

            // Translation Key
            TextFieldWithCount(
                label: "Translation Key",
                help: "Link this page to translations in other languages",
                text: $frontmatter.translationKey,
                placeholder: "translation-key"
            )

            // Markup
            TextFieldWithCount(
                label: "Markup",
                help: "Content format override (markdown, html, etc.)",
                text: $frontmatter.markup,
                placeholder: "markdown"
            )
        }
    }

    private func ensureBuildExists() {
        if frontmatter.build == nil {
            frontmatter.build = BuildOptions()
        }
    }

    private func toggleOutput(_ format: String, isOn: Bool) {
        var outputs = frontmatter.outputs ?? []
        if isOn {
            if !outputs.contains(format) {
                outputs.append(format)
            }
        } else {
            outputs.removeAll { $0 == format }
        }
        frontmatter.outputs = outputs.isEmpty ? nil : outputs
    }
}

#Preview {
    let frontmatter = Frontmatter(rawContent: "---\n---", format: .yaml)
    frontmatter.type = "post"
    frontmatter.layout = "single"
    frontmatter.build = BuildOptions(list: .always, render: .always, publishResources: true)
    frontmatter.outputs = ["html", "rss"]
    frontmatter.params = ["author": "Jane", "featured": true]

    return ScrollView {
        AdvancedTab(frontmatter: frontmatter)
            .padding()
    }
    .frame(width: 450, height: 800)
}
