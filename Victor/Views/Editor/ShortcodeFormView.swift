import SwiftUI

// MARK: - Shortcode Form View

/// Form view for configuring shortcode parameters and inserting
struct ShortcodeFormView: View {
    let shortcode: HugoShortcode
    let onInsert: (String) -> Void
    let onCancel: () -> Void

    @State private var parameterValues: [String: String] = [:]
    @State private var innerContent: String = ""
    @State private var showOptionalParams = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ShortcodeFormHeader(shortcode: shortcode)

            Divider()

            // Form content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Required parameters section
                    if !shortcode.requiredParameters.isEmpty {
                        ParameterSection(
                            title: "Required",
                            parameters: shortcode.requiredParameters,
                            values: $parameterValues
                        )
                    }

                    // Inner content for block shortcodes
                    if shortcode.hasClosingTag {
                        InnerContentSection(content: $innerContent)
                    }

                    // Optional parameters section (collapsible)
                    if !shortcode.optionalParameters.isEmpty {
                        OptionalParametersSection(
                            parameters: shortcode.optionalParameters,
                            values: $parameterValues,
                            isExpanded: $showOptionalParams
                        )
                    }

                    // Live preview
                    PreviewSection(preview: generatedShortcode)
                }
                .padding()
            }

            Divider()

            // Footer with buttons
            ShortcodeFormFooter(
                canInsert: canInsert,
                onCancel: onCancel,
                onInsert: { onInsert(generatedShortcode) }
            )
        }
        .frame(minWidth: AppConstants.Dialog.shortcodeFormWidth)
        .onAppear {
            // Initialize with default values
            for param in shortcode.parameters {
                if let defaultValue = param.defaultValue {
                    parameterValues[param.name] = defaultValue
                }
            }
        }
        .onChange(of: shortcode.id) { _, _ in
            // Reset when shortcode changes
            parameterValues = [:]
            innerContent = ""
            showOptionalParams = false
            for param in shortcode.parameters {
                if let defaultValue = param.defaultValue {
                    parameterValues[param.name] = defaultValue
                }
            }
        }
    }

    private var generatedShortcode: String {
        shortcode.generate(
            with: parameterValues,
            innerContent: shortcode.hasClosingTag ? (innerContent.isEmpty ? "content" : innerContent) : nil
        )
    }

    private var canInsert: Bool {
        // Check all required parameters are filled
        shortcode.requiredParameters.allSatisfy { param in
            guard let value = parameterValues[param.name] else { return false }
            return !value.isEmpty
        }
    }
}

// MARK: - Form Header

private struct ShortcodeFormHeader: View {
    let shortcode: HugoShortcode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: shortcode.icon)
                    .font(.title)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(shortcode.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(shortcode.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if !shortcode.detailedHelp.isEmpty {
                Text(shortcode.detailedHelp)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if shortcode.isDeprecated, let note = shortcode.deprecationNote {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(note)
                        .font(.callout)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding()
    }
}

// MARK: - Parameter Section

private struct ParameterSection: View {
    let title: String
    let parameters: [ShortcodeParameter]
    @Binding var values: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(parameters) { param in
                ParameterField(parameter: param, value: binding(for: param.name))
            }
        }
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(
            get: { values[name] ?? "" },
            set: { values[name] = $0 }
        )
    }
}

// MARK: - Parameter Field

private struct ParameterField: View {
    let parameter: ShortcodeParameter
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(parameter.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if parameter.isRequired {
                    Text("*")
                        .foregroundStyle(.red)
                }
            }

            Group {
                switch parameter.type {
                case .string, .int:
                    TextField(parameter.placeholder, text: $value)
                        .textFieldStyle(.roundedBorder)

                case .bool:
                    Toggle(isOn: boolBinding) {
                        Text(value == "true" ? "Enabled" : "Disabled")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .toggleStyle(.switch)

                case .enumeration(let options):
                    Picker("", selection: $value) {
                        Text("None").tag("")
                        ForEach(options, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .labelsHidden()
                }
            }

            if !parameter.helpText.isEmpty {
                Text(parameter.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: { value == "true" },
            set: { value = $0 ? "true" : "false" }
        )
    }
}

// MARK: - Inner Content Section

private struct InnerContentSection: View {
    @Binding var content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content")
                .font(.headline)
                .foregroundStyle(.secondary)

            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )

            Text("Content to place between the opening and closing tags")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Optional Parameters Section

private struct OptionalParametersSection: View {
    let parameters: [ShortcodeParameter]
    @Binding var values: [String: String]
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(parameters) { param in
                    ParameterField(parameter: param, value: binding(for: param.name))
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Optional Parameters (\(parameters.count))")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(
            get: { values[name] ?? "" },
            set: { values[name] = $0 }
        )
    }
}

// MARK: - Preview Section

private struct PreviewSection: View {
    let preview: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(preview)
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .textSelection(.enabled)
        }
    }
}

// MARK: - Form Footer

private struct ShortcodeFormFooter: View {
    let canInsert: Bool
    let onCancel: () -> Void
    let onInsert: () -> Void

    var body: some View {
        HStack {
            if !canInsert {
                Label("Fill required fields", systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Cancel", role: .cancel, action: onCancel)
                .keyboardShortcut(.escape)

            Button("Insert", action: onInsert)
                .keyboardShortcut(.return)
                .disabled(!canInsert)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    ShortcodeFormView(
        shortcode: HugoShortcode.allShortcodes[0],
        onInsert: { print($0) },
        onCancel: {}
    )
    .frame(width: 500, height: 600)
}
