import SwiftUI

/// Recursive `[String: Any]` / `[Any]` / scalar editor family, extracted from
/// `DataFileEditorView` (Config Editor v2 Phase 2, CONFIG-SCHEMA-SPEC §3.7) so
/// it has two call sites: the data-file form editor (`DataFormEditorView`)
/// and the Hugo Config Editor's Advanced tab (`ConfigAdvancedTab` — Site
/// Params, unknown-keys sections).
///
/// Both call sites follow the same two-closure shape already established by
/// `DataFormEditorView`: the `Binding`'s `set` performs the actual
/// persistent write (into `DataFile.data` or a `ConfigValueStore` subtree),
/// and `onChanged` is the caller's own "I just persisted, now sync/commit"
/// hook (`markChanged()` for data files, `configCommitAction` for config).
/// Neither call site needs `onChanged` to also carry the value — it's a
/// pure "something changed" signal.
///
/// Typing-latency note (CLAUDE.md Per-Keystroke Invalidation Contract,
/// CONFIG-SCHEMA-SPEC §2.8): scalar text/number leaves hold a local `@State`
/// draft and commit to their binding on blur/submit only — the same pattern
/// as `ConfigFieldView`'s `ConfigTextDraftRow`/`ConfigIntFieldRow`. This
/// matters now that the family is reachable from the config editor, whose
/// contract forbids per-keystroke writes; it's a behavior-preserving change
/// for the data-file editor too (edits still land, just on blur instead of
/// every keystroke — fewer redundant re-serializations of `DataFile.rawContent`).
/// Toggles commit immediately: a checkbox flip is one discrete edit, not a
/// keystroke stream, so no draft state is needed there.

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
            if item is [String: Any] {
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
                    .accessibilityLabel("Move Up")
                }

                if let onMoveDown = onMoveDown {
                    Button {
                        onMoveDown()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Move Down")
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete Item \(index + 1)")
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
            .accessibilityLabel("Delete \(key)")
        }
    }
}

// MARK: - Value Editor

struct DataValueEditor: View {
    @Binding var value: Any
    let onChanged: () -> Void

    var body: some View {
        Group {
            if value is String {
                DataScalarTextRow(value: $value, onChanged: onChanged)
            } else if let boolValue = value as? Bool {
                Toggle("", isOn: Binding(
                    get: { boolValue },
                    set: { value = $0; onChanged() }
                ))
                .toggleStyle(.checkbox)
            } else if value is Int {
                DataScalarIntRow(value: $value, onChanged: onChanged)
            } else if value is Double {
                DataScalarDoubleRow(value: $value, onChanged: onChanged)
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

// MARK: - Scalar draft-commit rows (typing-latency contract)
//
// Local `@State` draft, committed to `value` on blur/submit only — never per
// keystroke. Generalizes `ConfigFieldView.ConfigTextDraftRow`/
// `ConfigIntFieldRow`/`ConfigDoubleFieldRow` for a plain `Binding<Any>`
// rather than a `ConfigValueStore` key path.

private struct DataScalarTextRow: View {
    @Binding var value: Any
    let onChanged: () -> Void

    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    private var stored: String { value as? String ?? "" }

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit { commit() }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onAppear { draft = stored }
            .onChange(of: stored) { _, newValue in
                if !isFocused { draft = newValue }
            }
    }

    private func commit() {
        guard draft != stored else { return }
        value = draft
        onChanged()
    }
}

private struct DataScalarIntRow: View {
    @Binding var value: Any
    let onChanged: () -> Void

    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    private var stored: Int { value as? Int ?? 0 }

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.roundedBorder)
            .frame(width: 100)
            .focused($isFocused)
            .onSubmit { commit() }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onAppear { draft = String(stored) }
            .onChange(of: stored) { _, newValue in
                if !isFocused { draft = String(newValue) }
            }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard let parsed = Int(trimmed) else {
            draft = String(stored) // not parseable: revert rather than write garbage
            return
        }
        guard parsed != stored else { return }
        value = parsed
        onChanged()
    }
}

private struct DataScalarDoubleRow: View {
    @Binding var value: Any
    let onChanged: () -> Void

    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    private var stored: Double { value as? Double ?? 0 }

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.roundedBorder)
            .frame(width: 100)
            .focused($isFocused)
            .onSubmit { commit() }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onAppear { draft = String(stored) }
            .onChange(of: stored) { _, newValue in
                if !isFocused { draft = String(newValue) }
            }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard let parsed = Double(trimmed) else {
            draft = String(stored)
            return
        }
        guard parsed != stored else { return }
        value = parsed
        onChanged()
    }
}
