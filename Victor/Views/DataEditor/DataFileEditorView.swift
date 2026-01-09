import SwiftUI

/// Main view for editing Hugo data files (YAML/JSON/TOML)
struct DataFileEditorView: View {
    @Bindable var dataFile: DataFile
    let onSave: () async -> Void

    @State private var showRawEditor = false
    @State private var isSaving = false
    @State private var showSavedIndicator = false
    @State private var parseError: String?

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
            if oldValue == false && newValue == true {
                // Form → Raw: serialize current data to rawContent
                do {
                    let serialized = try DataFileParser.shared.serialize(dataFile)
                    dataFile.updateRawContent(serialized)
                } catch {
                    parseError = "Failed to serialize: \(error.localizedDescription)"
                }
            } else if oldValue == true && newValue == false {
                // Raw → Form: parse rawContent back to data
                do {
                    let parsed = try DataFileParser.shared.parse(
                        content: dataFile.rawContent,
                        format: dataFile.format
                    )
                    dataFile.data = parsed
                    parseError = nil
                } catch {
                    parseError = error.localizedDescription
                }
            }
        }
        .alert("Parse Error", isPresented: Binding(
            get: { parseError != nil },
            set: { if !$0 { parseError = nil } }
        )) {
            Button("OK") { parseError = nil }
        } message: {
            if let error = parseError {
                Text("Could not parse the raw content: \(error)")
            }
        }
    }

    private var dataToolbar: some View {
        HStack {
            Image(systemName: "doc.badge.gearshape")
                .foregroundStyle(.purple)

            Text(dataFile.fileName)
                .font(.headline)

            Text(dataFile.format.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.2))
                .cornerRadius(4)

            if dataFile.isArrayRoot {
                Text("Array")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.1))
                    .cornerRadius(4)
            }

            if dataFile.hasUnsavedChanges {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Unsaved changes")
                    .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
            }

            if showSavedIndicator {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .accessibilityLabel("Saved")
                    .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
            }

            Spacer()

            Picker("View", selection: $showRawEditor) {
                Text("Form").tag(false)
                Text("Raw").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)

            Divider()
                .frame(height: 20)

            Button {
                Task {
                    isSaving = true
                    await onSave()
                    isSaving = false
                    showSavedIndicatorBriefly()
                }
            } label: {
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .disabled(!dataFile.hasUnsavedChanges || isSaving)
            .keyboardShortcut("s", modifiers: .command)
            .help("Save (⌘S)")

            Button {
                NSWorkspace.shared.open(dataFile.url)
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .help("Open in default app")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: dataFile.hasUnsavedChanges)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: showSavedIndicator)
    }

    private func showSavedIndicatorBriefly() {
        showSavedIndicator = true
        Task {
            try? await Task.sleep(for: .seconds(2.0))
            showSavedIndicator = false
        }
    }
}

// MARK: - Form Editor

struct DataFormEditorView: View {
    @Bindable var dataFile: DataFile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if dataFile.isArrayRoot {
                    DataArrayEditor(
                        data: Binding(
                            get: { dataFile.dataArray ?? [] },
                            set: { dataFile.data = $0 }
                        ),
                        onChanged: { markChanged() }
                    )
                } else if let dict = dataFile.dataDictionary {
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
            .padding()
        }
    }

    private func markChanged() {
        // Serialize to update rawContent for change detection
        if let serialized = try? DataFileParser.shared.serialize(dataFile) {
            dataFile.updateRawContent(serialized)
        }
    }
}

// MARK: - Dictionary Editor

struct DataDictionaryEditor: View {
    @Binding var data: [String: Any]
    let onChanged: () -> Void

    @State private var newKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(data.keys.sorted()), id: \.self) { key in
                DataFieldRow(
                    key: key,
                    value: Binding(
                        get: { data[key] ?? "" },
                        set: { newValue in
                            data[key] = newValue
                            onChanged()
                        }
                    ),
                    onDelete: {
                        data.removeValue(forKey: key)
                        onChanged()
                    }
                )
            }

            // Add new field
            HStack {
                TextField("New field name", text: $newKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                Button("Add Field") {
                    if !newKey.isEmpty && data[newKey] == nil {
                        data[newKey] = ""
                        onChanged()
                        newKey = ""
                    }
                }
                .disabled(newKey.isEmpty)
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Array Editor

struct DataArrayEditor: View {
    @Binding var data: [Any]
    let onChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                DataArrayItemRow(
                    index: index,
                    item: Binding(
                        get: { data[index] },
                        set: { newValue in
                            data[index] = newValue
                            onChanged()
                        }
                    ),
                    onDelete: {
                        data.remove(at: index)
                        onChanged()
                    },
                    onMoveUp: index > 0 ? {
                        data.swapAt(index, index - 1)
                        onChanged()
                    } : nil,
                    onMoveDown: index < data.count - 1 ? {
                        data.swapAt(index, index + 1)
                        onChanged()
                    } : nil
                )
            }

            Button {
                data.append([:] as [String: Any])
                onChanged()
            } label: {
                Label("Add Item", systemImage: "plus")
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Array Item Row

struct DataArrayItemRow: View {
    let index: Int
    @Binding var item: Any
    let onDelete: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if let dict = item as? [String: Any] {
                DataDictionaryEditor(
                    data: Binding(
                        get: { item as? [String: Any] ?? [:] },
                        set: { item = $0 }
                    ),
                    onChanged: {}
                )
                .padding(.leading, 16)
            } else {
                DataValueEditor(
                    value: $item,
                    onChanged: {}
                )
            }
        } label: {
            HStack {
                Text("Item \(index + 1)")
                    .font(.headline)

                Spacer()

                if let onMoveUp = onMoveUp {
                    Button {
                        onMoveUp()
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                }

                if let onMoveDown = onMoveDown {
                    Button {
                        onMoveDown()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Field Row

struct DataFieldRow: View {
    let key: String
    @Binding var value: Any
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)

            DataValueEditor(value: $value, onChanged: {})

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Value Editor

struct DataValueEditor: View {
    @Binding var value: Any
    let onChanged: () -> Void

    var body: some View {
        Group {
            if let stringValue = value as? String {
                TextField("", text: Binding(
                    get: { stringValue },
                    set: { value = $0; onChanged() }
                ))
                .textFieldStyle(.roundedBorder)
            } else if let boolValue = value as? Bool {
                Toggle("", isOn: Binding(
                    get: { boolValue },
                    set: { value = $0; onChanged() }
                ))
                .toggleStyle(.checkbox)
            } else if let intValue = value as? Int {
                TextField("", value: Binding(
                    get: { intValue },
                    set: { value = $0; onChanged() }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
            } else if let doubleValue = value as? Double {
                TextField("", value: Binding(
                    get: { doubleValue },
                    set: { value = $0; onChanged() }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
            } else if let arrayValue = value as? [Any] {
                VStack(alignment: .leading) {
                    Text("[\(arrayValue.count) items]")
                        .foregroundStyle(.secondary)
                    DataArrayEditor(
                        data: Binding(
                            get: { value as? [Any] ?? [] },
                            set: { value = $0; onChanged() }
                        ),
                        onChanged: onChanged
                    )
                }
            } else if let dictValue = value as? [String: Any] {
                VStack(alignment: .leading) {
                    Text("{\(dictValue.count) fields}")
                        .foregroundStyle(.secondary)
                    DataDictionaryEditor(
                        data: Binding(
                            get: { value as? [String: Any] ?? [:] },
                            set: { value = $0; onChanged() }
                        ),
                        onChanged: onChanged
                    )
                }
            } else {
                Text(String(describing: value))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Raw Editor

struct DataRawEditorView: View {
    @Bindable var dataFile: DataFile
    @State private var editableContent: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
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
