import SwiftUI

/// Model for a translation entry
struct TranslationEntry: Identifiable {
    let id: UUID
    var key: String
    var value: String
    /// Plural forms (other, one, few, many, zero)
    var pluralForms: [String: String]?

    var hasPluralForms: Bool {
        pluralForms != nil && !(pluralForms?.isEmpty ?? true)
    }

    init(key: String, value: String, pluralForms: [String: String]? = nil) {
        self.id = UUID()
        self.key = key
        self.value = value
        self.pluralForms = pluralForms
    }
}

/// Main view for editing Hugo i18n translation files
struct TranslationEditorView: View {
    @Bindable var dataFile: DataFile
    let onSave: () async -> Void

    @State private var entries: [TranslationEntry] = []
    @State private var searchQuery = ""
    @State private var showRawEditor = false
    @State private var isSaving = false
    @State private var showSavedIndicator = false
    @State private var newKey = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var filteredEntries: [TranslationEntry] {
        guard !searchQuery.isEmpty else { return entries }
        return entries.filter { entry in
            entry.key.localizedCaseInsensitiveContains(searchQuery) ||
            entry.value.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            translationToolbar
            Divider()

            if showRawEditor {
                TranslationRawEditorView(dataFile: dataFile)
            } else {
                translationFormEditor
            }
        }
        .onAppear {
            loadEntries()
        }
        .onChange(of: showRawEditor) { oldValue, newValue in
            if oldValue == false && newValue == true {
                // Form → Raw: serialize entries
                syncEntriesToDataFile()
            } else if oldValue == true && newValue == false {
                // Raw → Form: reload entries
                loadEntries()
            }
        }
    }

    private var translationToolbar: some View {
        HStack {
            Image(systemName: "globe")
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            Text(dataFile.fileName)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            // Language badge
            Text(languageCode.uppercased())
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.blue)
                .cornerRadius(4)

            Text(dataFile.format.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.2))
                .cornerRadius(4)

            FileStatusBadgeView(
                hasUnsavedChanges: dataFile.hasUnsavedChanges,
                showSavedIndicator: showSavedIndicator
            )

            Spacer()

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search translations", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .frame(width: 150)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear Search")
                }
            }
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)

            FormRawPickerView(
                showRawEditor: $showRawEditor,
                width: AppConstants.Toolbar.viewIconLabelFrameWidth
            )

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

    private var translationFormEditor: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 200, alignment: .leading)

                Text("Translation")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Entries list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredEntries) { entry in
                        TranslationKeyRow(
                            entry: bindingFor(entry),
                            onDelete: { deleteEntry(entry) },
                            onChanged: { markChanged() }
                        )
                        Divider()
                    }

                    // Add new key
                    HStack {
                        TextField("New key", text: $newKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)

                        Button("Add") {
                            addEntry()
                        }
                        .disabled(newKey.isEmpty || entries.contains { $0.key == newKey })

                        Spacer()
                    }
                    .padding()
                }
            }

            // Footer stats
            HStack {
                Text("\(entries.count) translations")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !searchQuery.isEmpty {
                    Text("(\(filteredEntries.count) shown)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    /// Extract language code from filename (e.g., "en" from "en.yaml")
    private var languageCode: String {
        dataFile.url.deletingPathExtension().lastPathComponent
    }

    private func loadEntries() {
        entries = []

        guard let dict = dataFile.dataDictionary else { return }

        for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
            if let stringValue = value as? String {
                entries.append(TranslationEntry(key: key, value: stringValue))
            } else if let dictValue = value as? [String: Any] {
                // Complex entry with possible plural forms
                var pluralForms: [String: String] = [:]
                var otherValue = ""

                for (subKey, subValue) in dictValue {
                    if let str = subValue as? String {
                        if subKey == "other" {
                            otherValue = str
                        }
                        pluralForms[subKey] = str
                    }
                }

                entries.append(TranslationEntry(
                    key: key,
                    value: otherValue,
                    pluralForms: pluralForms.isEmpty ? nil : pluralForms
                ))
            }
        }
    }

    private func syncEntriesToDataFile() {
        var dict: [String: Any] = [:]

        for entry in entries {
            if let pluralForms = entry.pluralForms, !pluralForms.isEmpty {
                // Store as nested dictionary with plural forms
                dict[entry.key] = pluralForms
            } else {
                // Simple string value
                dict[entry.key] = entry.value
            }
        }

        dataFile.data = dict

        if let serialized = try? DataFileParser.shared.serialize(dataFile) {
            dataFile.updateRawContent(serialized)
        }
    }

    private func bindingFor(_ entry: TranslationEntry) -> Binding<TranslationEntry> {
        Binding(
            get: {
                entries.first { $0.id == entry.id } ?? entry
            },
            set: { newValue in
                if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                    entries[index] = newValue
                }
            }
        )
    }

    private func addEntry() {
        guard !newKey.isEmpty else { return }
        entries.append(TranslationEntry(key: newKey, value: ""))
        newKey = ""
        markChanged()
    }

    private func deleteEntry(_ entry: TranslationEntry) {
        entries.removeAll { $0.id == entry.id }
        markChanged()
    }

    private func markChanged() {
        syncEntriesToDataFile()
    }

    private func save() async {
        let helper = EditorSaveHelper()
        var errorMessage: String?
        await helper.performSave(
            operation: {
                syncEntriesToDataFile()
                await onSave()
            },
            isSaving: { isSaving },
            setIsSaving: { isSaving = $0 },
            showSavedIndicator: { showSavedIndicator },
            setShowSavedIndicator: { showSavedIndicator = $0 },
            errorMessage: { errorMessage },
            setErrorMessage: { errorMessage = $0 },
            afterSave: {}
        )
    }
}

// MARK: - Translation Key Row

struct TranslationKeyRow: View {
    @Binding var entry: TranslationEntry
    let onDelete: () -> Void
    let onChanged: () -> Void

    @State private var showPluralForms = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                // Key
                Text(entry.key)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 200, alignment: .leading)

                // Value
                TextField("Translation", text: $entry.value)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: entry.value) { _, _ in
                        onChanged()
                    }

                // Plural toggle
                if entry.hasPluralForms {
                    Button {
                        showPluralForms.toggle()
                    } label: {
                        Image(systemName: showPluralForms ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .help("Show plural forms")
                    .accessibilityLabel("Plural Forms")
                    .accessibilityValue(showPluralForms ? "Expanded" : "Collapsed")
                }

                // Delete button
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete Translation for \(entry.key)")
            }

            // Plural forms expansion
            if entry.hasPluralForms && showPluralForms {
                VStack(alignment: .leading, spacing: 4) {
                    if let pluralForms = entry.pluralForms {
                        ForEach(Array(pluralForms.keys.sorted()), id: \.self) { form in
                            HStack {
                                Text(form)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .trailing)

                                TextField(form, text: Binding(
                                    get: { pluralForms[form] ?? "" },
                                    set: { newValue in
                                        var updated = entry.pluralForms ?? [:]
                                        updated[form] = newValue
                                        entry.pluralForms = updated
                                        onChanged()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                }
                .padding(.leading, 216)  // Align with value column
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Raw Editor

struct TranslationRawEditorView: View {
    @Bindable var dataFile: DataFile
    @State private var editableContent: String = ""

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

            TextEditor(text: $editableContent)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: editableContent) { _, newValue in
                    dataFile.updateRawContent(newValue)
                }
        }
        .onAppear {
            editableContent = dataFile.rawContent
        }
    }
}
