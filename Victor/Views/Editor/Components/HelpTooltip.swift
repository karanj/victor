import SwiftUI

/// A help icon with tooltip for inline field documentation
struct HelpTooltip: View {
    let text: String

    var body: some View {
        Image(systemName: "questionmark.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(text)
    }
}

/// A form field with label, help tooltip, and content
struct FormFieldWithHelp<Content: View>: View {
    let label: String
    let help: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HelpTooltip(text: help)
            }
            content
        }
    }
}

/// A section header with optional help tooltip
struct SectionHeader: View {
    let title: String
    let help: String?

    init(_ title: String, help: String? = nil) {
        self.title = title
        self.help = help
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if let help = help {
                HelpTooltip(text: help)
            }

            Spacer()
        }
        .padding(.top, 8)
    }
}

/// An optional date field with toggle and date picker
struct OptionalDateField: View {
    let label: String
    let help: String
    @Binding var date: Date?

    var body: some View {
        FormFieldWithHelp(label: label, help: help) {
            HStack {
                Toggle("", isOn: Binding(
                    get: { date != nil },
                    set: { isOn in
                        date = isOn ? Date() : nil
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()

                if date != nil {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { date ?? Date() },
                            set: { date = $0 }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                } else {
                    Text("Not set")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }

                Spacer()
            }
        }
    }
}

/// A number input field with stepper
struct NumberField: View {
    let label: String
    let help: String
    @Binding var value: Int?
    let placeholder: String

    var body: some View {
        FormFieldWithHelp(label: label, help: help) {
            HStack {
                Toggle("", isOn: Binding(
                    get: { value != nil },
                    set: { isOn in
                        value = isOn ? 0 : nil
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()

                if value != nil {
                    TextField(placeholder, value: Binding(
                        get: { value ?? 0 },
                        set: { value = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)

                    Stepper("", value: Binding(
                        get: { value ?? 0 },
                        set: { value = $0 }
                    ))
                    .labelsHidden()
                } else {
                    Text("Not set")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }

                Spacer()
            }
        }
    }
}

/// A text field with character count indicator
struct TextFieldWithCount: View {
    let label: String
    let help: String
    @Binding var text: String?
    let placeholder: String
    let idealLength: Int?
    let maxLength: Int?

    init(
        label: String,
        help: String,
        text: Binding<String?>,
        placeholder: String = "",
        idealLength: Int? = nil,
        maxLength: Int? = nil
    ) {
        self.label = label
        self.help = help
        self._text = text
        self.placeholder = placeholder
        self.idealLength = idealLength
        self.maxLength = maxLength
    }

    var body: some View {
        FormFieldWithHelp(label: label, help: help) {
            VStack(alignment: .trailing, spacing: 2) {
                TextField(placeholder, text: Binding(
                    get: { text ?? "" },
                    set: { text = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)

                if idealLength != nil || maxLength != nil {
                    HStack {
                        Spacer()
                        Text(countText)
                            .font(.caption2)
                            .foregroundStyle(countColor)
                    }
                }
            }
        }
    }

    private var currentLength: Int {
        text?.count ?? 0
    }

    private var countText: String {
        if let max = maxLength {
            return "\(currentLength)/\(max)"
        } else if let ideal = idealLength {
            return "\(currentLength) (ideal: \(ideal))"
        }
        return "\(currentLength)"
    }

    private var countColor: Color {
        if let max = maxLength, currentLength > max {
            return .red
        } else if let ideal = idealLength, currentLength > ideal {
            return .orange
        }
        return .secondary
    }
}

/// A text editor with character count indicator (for multi-line text)
struct TextEditorWithCount: View {
    let label: String
    let help: String
    @Binding var text: String?
    let idealLength: Int?
    let maxLength: Int?
    let height: CGFloat

    init(
        label: String,
        help: String,
        text: Binding<String?>,
        idealLength: Int? = nil,
        maxLength: Int? = nil,
        height: CGFloat = 60
    ) {
        self.label = label
        self.help = help
        self._text = text
        self.idealLength = idealLength
        self.maxLength = maxLength
        self.height = height
    }

    var body: some View {
        FormFieldWithHelp(label: label, help: help) {
            VStack(alignment: .trailing, spacing: 2) {
                TextEditor(text: Binding(
                    get: { text ?? "" },
                    set: { text = $0.isEmpty ? nil : $0 }
                ))
                .frame(height: height)
                .font(.body)
                .border(Color(nsColor: .separatorColor), width: 1)

                if idealLength != nil || maxLength != nil {
                    HStack {
                        Spacer()
                        Text(countText)
                            .font(.caption2)
                            .foregroundStyle(countColor)
                    }
                }
            }
        }
    }

    private var currentLength: Int {
        text?.count ?? 0
    }

    private var countText: String {
        if let max = maxLength {
            return "\(currentLength)/\(max)"
        } else if let ideal = idealLength {
            return "\(currentLength) (ideal: \(ideal))"
        }
        return "\(currentLength)"
    }

    private var countColor: Color {
        if let max = maxLength, currentLength > max {
            return .red
        } else if let ideal = idealLength, currentLength > ideal {
            return .orange
        }
        return .secondary
    }
}

#Preview {
    VStack(spacing: 16) {
        FormFieldWithHelp(label: "Title", help: "The main title of your page") {
            TextField("Enter title", text: .constant("My Blog Post"))
                .textFieldStyle(.roundedBorder)
        }

        OptionalDateField(
            label: "Publish Date",
            help: "Content won't appear until this date",
            date: .constant(Date())
        )

        NumberField(
            label: "Weight",
            help: "Lower numbers appear first in lists",
            value: .constant(10),
            placeholder: "0"
        )

        TextFieldWithCount(
            label: "Description",
            help: "Meta description for search engines",
            text: .constant("A sample description"),
            placeholder: "Enter description",
            idealLength: 150,
            maxLength: 160
        )
    }
    .padding()
    .frame(width: 400)
}
