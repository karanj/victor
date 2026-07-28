import SwiftUI

/// Main view for editing Hugo data files (YAML/JSON/TOML)
struct DataFileEditorView: View {
    @Bindable var dataFile: DataFile
    /// Returns false if the save failed - the caller has already surfaced the error.
    let onSave: () async -> Bool

    @State private var showRawEditor = false
    @State private var isSaving = false
    @State private var showSavedIndicator = false
    @State private var parseError: String?
    /// Set while `onChange` puts `showRawEditor` back after a failed conversion, so the
    /// resulting second `onChange` doesn't run the opposite (stale) conversion.
    @State private var isRevertingMode = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            dataToolbar
            Divider()

            if showRawEditor {
                DataRawEditorView(dataFile: dataFile)
            } else {
                DataFormEditorView(dataFile: dataFile)
            }
        }
        .onChange(of: showRawEditor) { oldValue, newValue in
            guard !isRevertingMode else {
                isRevertingMode = false
                return
            }

            let converted: Bool
            if newValue {
                converted = FormRawToggleHandler.handleFormToRaw(
                    serializeToRaw: {
                        let serialized = try DataFileParser.shared.serialize(dataFile)
                        dataFile.updateRawContent(serialized)
                    },
                    parseError: &parseError
                )
            } else {
                converted = FormRawToggleHandler.handleRawToForm(
                    parseFromRaw: {
                        let parsed = try DataFileParser.shared.parse(
                            content: dataFile.rawContent,
                            format: dataFile.format
                        )
                        dataFile.data = parsed
                    },
                    parseError: &parseError
                )
            }

            if !converted {
                isRevertingMode = true
                showRawEditor = oldValue
            }
        }
        .parseErrorAlert($parseError)
    }

    private var dataToolbar: some View {
        HStack {
            Image(systemName: "doc.badge.gearshape")
                .foregroundStyle(.purple)
                .accessibilityHidden(true)

            Text(dataFile.fileName)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text(dataFile.format.displayName)
                .badgeStyle(color: .secondary, font: Font.caption, backgroundOpacity: 0.2)

            if dataFile.isArrayRoot {
                Text("Array")
                    .badgeStyle(color: .blue, font: Font.caption, backgroundOpacity: 0.1)
            }

            FileStatusBadgeView(
                hasUnsavedChanges: dataFile.hasUnsavedChanges,
                showSavedIndicator: showSavedIndicator
            )

            Spacer()

            FormRawPickerView(showRawEditor: $showRawEditor)

            EditorToolbarDivider()

            EditorSaveButton(
                isSaving: isSaving,
                hasUnsavedChanges: dataFile.hasUnsavedChanges,
                action: save
            )

            EditorOpenExternalButton(url: dataFile.url)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.fast), value:dataFile.hasUnsavedChanges)
        .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.fast), value:showSavedIndicator)
    }

    // MARK: - Actions

    private func save() async {
        let helper = EditorSaveHelper()
        await helper.performSave(
            operation: {
                guard await onSave() else { throw EditorSaveFailure.alreadyReported }
            },
            setIsSaving: { isSaving = $0 },
            setShowSavedIndicator: { showSavedIndicator = $0 },
            setErrorMessage: { _ in },  // SiteViewModel's alert already reported it
            afterSave: {}
        )
    }
}

// MARK: - Form Editor

struct DataFormEditorView: View {
    @Bindable var dataFile: DataFile

    /// `Form(.grouped)`, not a plain `ScrollView`: the recursive editor emits
    /// bare rows that need a Form's label column (see `RecursiveValueEditor`).
    var body: some View {
        Form {
            if dataFile.isArrayRoot {
                DataArrayEditor(
                    data: Binding(
                        get: { dataFile.dataArray ?? [] },
                        set: { dataFile.data = $0 }
                    ),
                    onChanged: { markChanged() }
                )
            } else if dataFile.dataDictionary != nil {
                DataDictionaryEditor(
                    data: Binding(
                        get: { dataFile.dataDictionary ?? [:] },
                        set: { dataFile.data = $0 }
                    ),
                    onChanged: { markChanged() }
                )
            } else {
                Text("Unsupported data structure")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func markChanged() {
        // Serialize to update rawContent for change detection
        if let serialized = try? DataFileParser.shared.serialize(dataFile) {
            dataFile.updateRawContent(serialized)
        }
    }
}

// MARK: - Raw Editor
//
// The recursive editor family lives in `Views/Components/RecursiveValueEditor.swift`,
// shared with the config editor's Advanced tab.

struct DataRawEditorView: View {
    @Bindable var dataFile: DataFile
    @State private var editableContent: String = ""

    /// Map data file format to Highlightr language
    private var highlightrLanguage: String {
        switch dataFile.format {
        case .yaml:
            return "yaml"
        case .toml:
            return "ini" // Closest match for TOML
        case .json:
            return "json"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.Status.info)
                    .accessibilityHidden(true)
                Text("Changes made here will update the form view when you switch tabs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.blue.opacity(0.05))

            SyntaxHighlightedTextView(
                text: $editableContent,
                language: highlightrLanguage,
                onTextChange: {
                    dataFile.updateRawContent(editableContent)
                }
            )
        }
        .onAppear {
            editableContent = dataFile.rawContent
        }
    }
}

// MARK: - Previews

#Preview("Dictionary Data File") {
    let dataFile = DataFile(
        url: URL(fileURLWithPath: "/mock/data/authors.yaml"),
        format: .yaml,
        data: [
            "name": "Jane Doe",
            "email": "jane@example.com",
            "bio": "A software engineer passionate about SwiftUI."
        ],
        rawContent: """
        name: Jane Doe
        email: jane@example.com
        bio: A software engineer passionate about SwiftUI.
        """
    )
    return DataFileEditorView(dataFile: dataFile, onSave: { true })
        .frame(width: 600, height: 400)
}

#Preview("Array Data File") {
    let dataFile = DataFile(
        url: URL(fileURLWithPath: "/mock/data/social.json"),
        format: .json,
        data: [
            ["name": "Twitter", "url": "https://twitter.com/example"],
            ["name": "GitHub", "url": "https://github.com/example"],
            ["name": "LinkedIn", "url": "https://linkedin.com/in/example"]
        ],
        rawContent: """
        [
          {"name": "Twitter", "url": "https://twitter.com/example"},
          {"name": "GitHub", "url": "https://github.com/example"},
          {"name": "LinkedIn", "url": "https://linkedin.com/in/example"}
        ]
        """
    )
    return DataFileEditorView(dataFile: dataFile, onSave: { true })
        .frame(width: 600, height: 500)
}

#Preview("Empty Data File") {
    let dataFile = DataFile(
        url: URL(fileURLWithPath: "/mock/data/config.toml"),
        format: .toml,
        data: [:] as [String: Any],
        rawContent: ""
    )
    return DataFileEditorView(dataFile: dataFile, onSave: { true })
        .frame(width: 600, height: 400)
}
