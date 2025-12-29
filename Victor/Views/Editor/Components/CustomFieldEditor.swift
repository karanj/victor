import SwiftUI

/// Editor for custom frontmatter fields (params and customFields)
struct CustomFieldEditor: View {
    @Binding var fields: [String: Any]
    @State private var showAddField = false
    @State private var newFieldKey = ""
    @State private var newFieldValue = ""
    @State private var newFieldType: CustomFieldType = .string

    enum CustomFieldType: String, CaseIterable {
        case string = "String"
        case number = "Number"
        case boolean = "Boolean"
        case list = "List"

        func convert(_ value: String) -> Any {
            switch self {
            case .string:
                return value
            case .number:
                return Double(value) ?? Int(value) ?? 0
            case .boolean:
                return value.lowercased() == "true"
            case .list:
                return value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if fields.isEmpty && !showAddField {
                emptyState
            } else {
                // Existing fields
                ForEach(Array(fields.keys.sorted()), id: \.self) { key in
                    fieldRow(key: key, value: fields[key]!)
                }
            }

            // Add field form
            if showAddField {
                addFieldForm
            } else {
                Button(action: { showAddField = true }) {
                    Label("Add Custom Field", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.grid.1x2")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)

            Text("No custom fields")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Add custom parameters to extend your frontmatter.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func fieldRow(key: String, value: Any) -> some View {
        HStack {
            Text(key)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)

            Spacer()

            Text(displayValue(value))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(typeLabel(value))
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Button(action: { deleteField(key: key) }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var addFieldForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Custom Field")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Key", text: $newFieldKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)

                Picker("", selection: $newFieldType) {
                    ForEach(CustomFieldType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .labelsHidden()
                .frame(width: 80)

                TextField(valuePlaceholder, text: $newFieldValue)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    resetAddForm()
                }
                .buttonStyle(.plain)

                Button("Add") {
                    addField()
                }
                .disabled(newFieldKey.isEmpty || newFieldValue.isEmpty)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var valuePlaceholder: String {
        switch newFieldType {
        case .string: return "Value"
        case .number: return "0"
        case .boolean: return "true or false"
        case .list: return "item1, item2, item3"
        }
    }

    private func displayValue(_ value: Any) -> String {
        if let string = value as? String {
            return string
        } else if let number = value as? Int {
            return String(number)
        } else if let number = value as? Double {
            return String(number)
        } else if let bool = value as? Bool {
            return bool ? "true" : "false"
        } else if let array = value as? [String] {
            return array.joined(separator: ", ")
        } else if value is [String: Any] {
            return "[Object]"
        }
        return String(describing: value)
    }

    private func typeLabel(_ value: Any) -> String {
        if value is String {
            return "String"
        } else if value is Int || value is Double {
            return "Number"
        } else if value is Bool {
            return "Bool"
        } else if value is [Any] {
            return "List"
        } else if value is [String: Any] {
            return "Object"
        }
        return "Unknown"
    }

    private func addField() {
        let key = newFieldKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        fields[key] = newFieldType.convert(newFieldValue)
        resetAddForm()
    }

    private func deleteField(key: String) {
        fields.removeValue(forKey: key)
    }

    private func resetAddForm() {
        showAddField = false
        newFieldKey = ""
        newFieldValue = ""
        newFieldType = .string
    }
}

#Preview {
    @Previewable @State var fields: [String: Any] = [
        "author": "Jane Doe",
        "featured": true,
        "rating": 4.5,
        "related": ["post-1", "post-2"]
    ]

    return CustomFieldEditor(fields: $fields)
        .padding()
        .frame(width: 400)
}
