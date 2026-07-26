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
/// **Layout contract:** every editor emits bare rows — no wrapping
/// `VStack`/`ScrollView`, no self-drawn card chrome. Scalars are
/// `LabeledContent` so they inherit the host `Form`'s label column;
/// containers are `DisclosureGroup`. Both call sites host this inside
/// `Form { … }.formStyle(.grouped)`.
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

/// Shared with `ConfigFieldView` so both land on the same widths in the
/// Advanced tab's Form.
private let scalarFieldMaxWidth = AppConstants.FormField.textWidth
private let numericFieldWidth = AppConstants.FormField.numberWidth

/// A grouped `Form` doesn't indent rows a `DisclosureGroup` emits into it,
/// so nesting has to be drawn by hand. Accumulates per recursion level.
private let nestedRowIndent: CGFloat = 18

// MARK: - Dictionary Editor

/// One row per key plus an "add field" row.
struct DataDictionaryEditor: View {
    @Binding var data: [String: Any]
    let onChanged: () -> Void

    @State private var newKey = ""

    var body: some View {
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

        LabeledContent("Add Field") {
            HStack(spacing: 6) {
                // Titled `TextField`s render their label beside the box inside
                // a `LabeledContent` column, so use a prompt instead.
                TextField("", text: $newKey, prompt: Text("Field name"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: scalarFieldMaxWidth)
                    .onSubmit { addField() }
                Button("Add", action: addField)
                    .disabled(!canAddField)
            }
        }
    }

    private var canAddField: Bool {
        let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && data[trimmed] == nil
    }

    private func addField() {
        let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, data[trimmed] == nil else { return }
        data[trimmed] = ""
        onChanged()
        newKey = ""
    }
}

// MARK: - Array Editor

/// One row per element plus an "add item" row.
struct DataArrayEditor: View {
    @Binding var data: [Any]
    let onChanged: () -> Void

    var body: some View {
        ForEach(Array(data.enumerated()), id: \.offset) { index, _ in
            DataArrayItemRow(
                index: index,
                item: Binding(
                    get: { index < data.count ? data[index] : "" },
                    set: { newValue in
                        guard index < data.count else { return }
                        data[index] = newValue
                        onChanged()
                    }
                ),
                onDelete: {
                    guard index < data.count else { return }
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

        LabeledContent("Add Item") {
            Button {
                data.append([:] as [String: Any])
                onChanged()
            } label: {
                Label("Add", systemImage: "plus")
            }
            .accessibilityLabel("Add Item")
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
        if item is [String: Any] || item is [Any] {
            DisclosureGroup(isExpanded: $isExpanded) {
                DataValueEditor(value: $item, onChanged: {})
                    .padding(.leading, nestedRowIndent)
            } label: {
                header
            }
        } else {
            LabeledContent {
                HStack(spacing: 6) {
                    DataScalarEditor(value: $item, onChanged: {})
                    itemButtons
                }
            } label: {
                Text("Item \(index + 1)")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Item \(index + 1)")
            Spacer()
            Text(DataValueSummary.text(for: item))
                .countBadgeStyle()
            itemButtons
        }
    }

    @ViewBuilder
    private var itemButtons: some View {
        if let onMoveUp {
            Button(action: onMoveUp) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Move Item \(index + 1) Up")
        }

        if let onMoveDown {
            Button(action: onMoveDown) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Move Item \(index + 1) Down")
        }

        Button(role: .destructive, action: onDelete) {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Delete Item \(index + 1)")
    }
}

// MARK: - Field Row

/// One dictionary entry: scalars as a `LabeledContent` row, containers as a
/// `DisclosureGroup` headed by the key, a count badge, and delete.
struct DataFieldRow: View {
    let key: String
    @Binding var value: Any
    let onDelete: () -> Void

    @State private var isExpanded = true

    var body: some View {
        if value is [String: Any] || value is [Any] {
            DisclosureGroup(isExpanded: $isExpanded) {
                DataValueEditor(value: $value, onChanged: {})
                    .padding(.leading, nestedRowIndent)
            } label: {
                HStack(spacing: 6) {
                    keyLabel
                    Spacer()
                    Text(DataValueSummary.text(for: value))
                        .countBadgeStyle()
                    deleteButton
                }
            }
        } else {
            LabeledContent {
                HStack(spacing: 6) {
                    DataScalarEditor(value: $value, onChanged: {})
                    deleteButton
                }
            } label: {
                keyLabel
            }
        }
    }

    private var keyLabel: some View {
        Text(key)
            .font(.system(.body, design: .monospaced))
    }

    private var deleteButton: some View {
        Button(role: .destructive, action: onDelete) {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Delete \(key)")
    }
}

// MARK: - Value summary

/// Child-count text for a container's disclosure header.
enum DataValueSummary {
    static func text(for value: Any) -> String {
        if let dict = value as? [String: Any] {
            return "\(dict.count) field\(dict.count == 1 ? "" : "s")"
        }
        if let array = value as? [Any] {
            return "\(array.count) item\(array.count == 1 ? "" : "s")"
        }
        return ""
    }
}

// MARK: - Value Editor

/// Dispatches a value of unknown shape to the right editor.
struct DataValueEditor: View {
    @Binding var value: Any
    let onChanged: () -> Void

    var body: some View {
        if value is [String: Any] {
            DataDictionaryEditor(
                data: Binding(
                    get: { value as? [String: Any] ?? [:] },
                    set: { value = $0; onChanged() }
                ),
                onChanged: onChanged
            )
        } else if value is [Any] {
            DataArrayEditor(
                data: Binding(
                    get: { value as? [Any] ?? [] },
                    set: { value = $0; onChanged() }
                ),
                onChanged: onChanged
            )
        } else {
            DataScalarEditor(value: $value, onChanged: onChanged)
        }
    }
}

/// Scalar-only leaf, for callers that have already established the row and
/// just need a control for the content column.
struct DataScalarEditor: View {
    @Binding var value: Any
    let onChanged: () -> Void

    var body: some View {
        if value is String {
            DataScalarTextRow(value: $value, onChanged: onChanged)
        } else if let boolValue = value as? Bool {
            Toggle("", isOn: Binding(
                get: { boolValue },
                set: { value = $0; onChanged() }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
        } else if value is Int {
            DataScalarIntRow(value: $value, onChanged: onChanged)
        } else if value is Double {
            DataScalarDoubleRow(value: $value, onChanged: onChanged)
        } else {
            Text(String(describing: value))
                .foregroundStyle(.secondary)
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
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: scalarFieldMaxWidth)
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
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.leading)
            .frame(width: numericFieldWidth)
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
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.leading)
            .frame(width: numericFieldWidth)
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
