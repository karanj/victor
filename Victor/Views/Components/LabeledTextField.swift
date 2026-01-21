import SwiftUI

/// A labeled text field with consistent styling
///
/// Use this component outside of SwiftUI Forms for labeled text inputs.
/// Inside Forms, prefer using SwiftUI's `LabeledContent` or `Form` sections.
///
/// Usage:
/// ```swift
/// LabeledTextField(label: "Title", text: $title, placeholder: "Enter title")
/// LabeledTextField(label: "Email", text: $email, placeholder: "user@example.com")
/// ```
struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

/// A labeled text field that binds to an optional String
///
/// Converts nil to empty string and empty string back to nil.
struct OptionalLabeledTextField: View {
    let label: String
    @Binding var text: String?
    var placeholder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: Binding(
                get: { text ?? "" },
                set: { text = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }
}

/// A labeled text field with a help tooltip
///
/// Combines label, help icon, and text field in a compact layout.
/// For more complex field layouts, use `FormFieldWithHelp` from HelpTooltip.swift.
struct LabeledTextFieldWithHelp: View {
    let label: String
    let help: String
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(help)
            }
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Previews

#Preview("Basic") {
    VStack(spacing: 16) {
        LabeledTextField(
            label: "Title",
            text: .constant("My Blog Post"),
            placeholder: "Enter title"
        )

        LabeledTextField(
            label: "Author",
            text: .constant(""),
            placeholder: "Enter author name"
        )
    }
    .padding()
    .frame(width: 300)
}

#Preview("Optional") {
    VStack(spacing: 16) {
        OptionalLabeledTextField(
            label: "Subtitle",
            text: .constant("A great subtitle"),
            placeholder: "Optional subtitle"
        )

        OptionalLabeledTextField(
            label: "Excerpt",
            text: .constant(nil),
            placeholder: "Optional excerpt"
        )
    }
    .padding()
    .frame(width: 300)
}

#Preview("With Help") {
    LabeledTextFieldWithHelp(
        label: "Slug",
        help: "URL-friendly identifier for this page",
        text: .constant("my-blog-post"),
        placeholder: "url-slug"
    )
    .padding()
    .frame(width: 300)
}
