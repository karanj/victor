import SwiftUI

/// Generic type→control renderer for `ConfigSettingSpec` entries, backed
/// directly by `ConfigValueStore` (CONFIG-SCHEMA-SPEC §2.6).
///
/// This view is the **observation leaf** for the per-keystroke invalidation
/// contract (CLAUDE.md): it is the only place that reads `store.version` /
/// `store.value(at:)`. Parent tab bodies iterate the static
/// `[ConfigSettingSpec]` array and hand each row a `spec` + the shared
/// `store` reference — they never read a config computed accessor or a
/// store value themselves, so a keystroke inside one field invalidates only
/// that field's row, not the tab body, the toolbar, or `.commands`.
///
/// Text-like types (`string`, `duration`, `stringOrStringArray`) hold a
/// local `@State` draft and commit to the store on blur/submit — the
/// `PermalinkRowView` pattern (`ConfigContentTab.swift`) generalized.
/// Toggles/Pickers commit immediately: a toggle flip or a menu pick is one
/// discrete edit, not a keystroke stream.
struct ConfigFieldView: View {
    let spec: ConfigSettingSpec
    let store: ConfigValueStore
    var context: ValidationContext? = nil

    /// How a commit reaches `HugoConfig.syncRawContentFromStructuredData()`.
    /// An environment action (set once in `ConfigEditorView`, around the
    /// `TabView`) rather than a per-field closure parameter: every row below
    /// needs the same one call, and threading it through every
    /// `ConfigFieldView(...)` call site at every tab would be pure
    /// boilerplate repeated ~20 times across the 4 tabs for no benefit —
    /// the environment already exists for exactly this "one action, many
    /// leaves" shape. See `configCommitAction` below.
    @Environment(\.configCommitAction) private var commit

    var body: some View {
        // Establishes this row's (and only this row's) observation
        // dependency on `store.version`. `ConfigValueStore.root` itself is
        // `@ObservationIgnored` (CONFIG-SCHEMA-SPEC §2.2) so reading typed
        // accessors below does NOT subscribe this view on its own; reading
        // `.version` explicitly is what makes SwiftUI re-evaluate this row
        // (and nothing above it) after a `set`/`remove` call.
        let _ = store.version

        LabeledContent(spec.label) {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    control
                    resetButton
                }
                if let warning = validatorWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.Status.warning)
                }
                if let deprecation = spec.deprecation {
                    deprecationRow(deprecation)
                }
            }
        }
        .help(spec.help)
        .contextMenu {
            if store.isPresent(spec.key) {
                Button("Reset to Default", role: .destructive) {
                    store.remove(at: spec.key)
                    commit()
                }
            }
        }
    }

    // MARK: - Control dispatch

    @ViewBuilder
    private var control: some View {
        switch spec.type {
        case .bool:
            ConfigBoolFieldRow(spec: spec, store: store, commit: commit)

        case .string:
            ConfigTextDraftRow(
                spec: spec,
                store: store,
                commit: commit,
                displayText: { $0.stringValue(spec.key) },
                placeholderText: spec.defaultValue.stringValue ?? "",
                write: { text, store in store.set(text, at: spec.key) }
            )

        case .int:
            ConfigIntFieldRow(spec: spec, store: store, commit: commit)

        case .double:
            ConfigDoubleFieldRow(spec: spec, store: store, commit: commit)

        case .duration:
            ConfigTextDraftRow(
                spec: spec,
                store: store,
                commit: commit,
                displayText: { $0.stringValue(spec.key) },
                placeholderText: spec.defaultValue.stringValue ?? "",
                write: { text, store in store.set(text, at: spec.key) },
                trailingHint: "e.g. 60s, 30m, 1h"
            )

        case .stringArray:
            ConfigStringArrayFieldRow(spec: spec, store: store, commit: commit)

        case .choice(let options):
            ConfigChoiceFieldRow(spec: spec, options: options, store: store, commit: commit)

        case .stringOrStringArray:
            ConfigTextDraftRow(
                spec: spec,
                store: store,
                commit: commit,
                displayText: { store in
                    let raw = store.value(at: spec.key)
                    if raw is [Any] || raw is [String] {
                        return store.stringArrayValue(spec.key)?.joined(separator: ", ")
                    }
                    return store.stringValue(spec.key)
                },
                placeholderText: spec.defaultValue.stringValue
                    ?? spec.defaultValue.stringArrayValue?.joined(separator: ", ") ?? "",
                write: { text, store in
                    if text.contains(",") {
                        let parts = text.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        store.set(parts, at: spec.key)
                    } else {
                        store.set(text, at: spec.key)
                    }
                }
            )

        case .boolOrEnum(let options):
            ConfigBoolOrEnumFieldRow(spec: spec, options: options, store: store, commit: commit)

        case .boolOrSectionMap:
            ConfigBoolOrSectionMapFieldRow(spec: spec, store: store, commit: commit)

        // Later-phase recursive/raw types: no tab wires these yet.
        // Rendered as an inert, clearly-labeled row so the generic renderer
        // degrades safely if a future spec of one of these types is ever
        // passed to it before its dedicated editor (dictionary → Advanced
        // tab's `DataDictionaryEditor`, rawOnly → "Edit in Raw") ships.
        case .dictionary, .stringMap, .rawOnly:
            ConfigComingLaterRow(spec: spec)
        }
    }

    // MARK: - Reset affordance

    @ViewBuilder
    private var resetButton: some View {
        if store.isPresent(spec.key) {
            Button {
                store.remove(at: spec.key)
                commit()
            } label: {
                Image(systemName: "delete.left")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Reset \(spec.label) to default")
            .accessibilityLabel("Reset \(spec.label) to Default")
        }
    }

    // MARK: - Validation

    private var validatorWarning: String? {
        guard let validator = spec.validator, let context else { return nil }
        guard let raw = store.value(at: spec.key) else { return nil }
        return validator.validate(raw, context)
    }

    // MARK: - Deprecation

    @ViewBuilder
    private func deprecationRow(_ deprecation: ConfigDeprecation) -> some View {
        HStack(spacing: 6) {
            Text("Deprecated")
                .capsuleBadgeStyle(color: Color.Status.warning)
            Text(deprecation.message)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let replacementKey = deprecation.replacementKey {
                Button("Use \(replacementKey)") {
                    guard let raw = store.value(at: spec.key) else { return }
                    store.remove(at: spec.key)
                    store.set(raw, at: replacementKey)
                    commit()
                }
                .font(.caption2)
                .buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - Environment: commit action

/// The single write-back path from a `ConfigFieldView` commit to
/// `HugoConfig.hasUnsavedChanges` updating (CONFIG-SCHEMA-SPEC §2.8):
/// `HugoConfig.syncRawContentFromStructuredData()` recomputes `rawContent`
/// from the store, which is what the toolbar save button's
/// `hasUnsavedChanges` (== `rawContent != originalContent`) observes.
/// `ConfigEditorView` sets this once around the `TabView`; leaves never
/// reach for `HugoConfig` directly, so `ConfigFieldView` stays testable
/// against a bare `ConfigValueStore` with no `HugoConfig` in scope.
private struct ConfigCommitActionKey: EnvironmentKey {
    // The no-op default closure captures no state, so it's safe to share
    // across isolation domains even though `() -> Void` isn't provably
    // `Sendable` to the compiler.
    nonisolated(unsafe) static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var configCommitAction: () -> Void {
        get { self[ConfigCommitActionKey.self] }
        set { self[ConfigCommitActionKey.self] = newValue }
    }
}

// MARK: - ConfigDefault display helpers

private extension ConfigDefault {
    var stringValue: String? {
        switch self {
        case .value(let v): return v as? String
        case .sentinel(let v, _): return v as? String
        case .none: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .value(let v): return v as? Bool
        case .sentinel(let v, _): return v as? Bool
        case .none: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .value(let v): return v as? Int
        case .sentinel(let v, _): return v as? Int
        case .none: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .value(let v): return (v as? Double) ?? (v as? Int).map(Double.init)
        case .sentinel(let v, _): return (v as? Double) ?? (v as? Int).map(Double.init)
        case .none: return nil
        }
    }

    var stringArrayValue: [String]? {
        switch self {
        case .value(let v): return v as? [String]
        case .sentinel(let v, _): return v as? [String]
        case .none: return nil
        }
    }

    var sentinelMeaning: String? {
        if case .sentinel(_, let meaning) = self { return meaning }
        return nil
    }
}

// MARK: - Shared "default" tag

private struct DefaultValueTag: View {
    var body: some View {
        Text("default")
            .badgeStyle(color: .secondary)
    }
}

// MARK: - bool

private struct ConfigBoolFieldRow: View {
    let spec: ConfigSettingSpec
    let store: ConfigValueStore
    let commit: () -> Void

    private var defaultBool: Bool { spec.defaultValue.boolValue ?? false }
    private var isPresent: Bool { store.isPresent(spec.key) }

    /// `displayed`/`stored` are each other's inverse when
    /// `spec.invertedBoolLabel` is set, and the identity otherwise — applying
    /// either direction twice is a no-op, so one function covers both the
    /// toggle's `get` (stored → displayed) and `set` (displayed → stored).
    private func flip(_ value: Bool) -> Bool {
        spec.invertedBoolLabel ? !value : value
    }

    var body: some View {
        HStack(spacing: 6) {
            Toggle("", isOn: Binding(
                get: {
                    let stored = isPresent ? (store.boolValue(spec.key) ?? defaultBool) : defaultBool
                    return flip(stored)
                },
                set: { newDisplayValue in
                    store.set(flip(newDisplayValue), at: spec.key)
                    commit()
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .opacity(isPresent ? 1.0 : 0.6)

            if !isPresent {
                DefaultValueTag()
            }
        }
    }
}

// MARK: - boolOrSectionMap

/// `uglyURLs`-shaped fields: `bool` or a per-section `map[string]bool`
/// (CONFIG-SCHEMA-SPEC §2.6). A plain `Toggle` when the stored value is a
/// bool or absent; when it's a map, a read-only summary + "Edit in Raw"
/// button — the per-section shape isn't worth a bespoke sub-editor for one
/// field, and Raw mode already round-trips it losslessly.
private struct ConfigBoolOrSectionMapFieldRow: View {
    let spec: ConfigSettingSpec
    let store: ConfigValueStore
    let commit: () -> Void

    @Environment(\.configSwitchToRawAction) private var switchToRaw

    private var defaultBool: Bool { spec.defaultValue.boolValue ?? false }
    private var isPresent: Bool { store.isPresent(spec.key) }
    private var rawValue: Any? { store.value(at: spec.key) }
    private var sectionMap: [String: Any]? {
        guard let dict = rawValue as? [String: Any], !(rawValue is Bool) else { return nil }
        return dict
    }

    var body: some View {
        if let sectionMap {
            HStack(spacing: 6) {
                Text("Per-section map (\(sectionMap.count)) — edit in Raw")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Edit in Raw") { switchToRaw() }
                    .buttonStyle(.borderless)
            }
        } else {
            HStack(spacing: 6) {
                Toggle("", isOn: Binding(
                    get: { isPresent ? (store.boolValue(spec.key) ?? defaultBool) : defaultBool },
                    set: { newValue in
                        store.set(newValue, at: spec.key)
                        commit()
                    }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .opacity(isPresent ? 1.0 : 0.6)

                if !isPresent {
                    DefaultValueTag()
                }
            }
        }
    }
}

// MARK: - choice

/// Dispatches between the plain menu `Picker` and the filterable popover
/// variant purely on case count — not on which key it is — so any `.choice`
/// spec that grows past the threshold (not just `markup.highlight.style`'s
/// 74 chroma styles) gets the searchable control automatically.
private struct ConfigChoiceFieldRow: View {
    let spec: ConfigSettingSpec
    let options: [String]
    let store: ConfigValueStore
    let commit: () -> Void

    /// A plain `Picker(.menu)` with ~15 items is still a single readable
    /// dropdown; past that (chroma styles' 74) it becomes an unusable wall
    /// of text, hence the searchable popover.
    private static let searchableThreshold = 15

    var body: some View {
        if options.count > Self.searchableThreshold {
            ConfigSearchableChoiceFieldRow(spec: spec, options: options, store: store, commit: commit)
        } else {
            ConfigMenuChoiceFieldRow(spec: spec, options: options, store: store, commit: commit)
        }
    }
}

private struct ConfigMenuChoiceFieldRow: View {
    let spec: ConfigSettingSpec
    let options: [String]
    let store: ConfigValueStore
    let commit: () -> Void

    private static let defaultTag = "__default__"

    private var defaultString: String { spec.defaultValue.stringValue ?? "" }
    private var isPresent: Bool { store.isPresent(spec.key) }
    private var current: String { store.stringValue(spec.key) ?? defaultString }

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: Binding(
                get: { isPresent ? current : Self.defaultTag },
                set: { newValue in
                    if newValue == Self.defaultTag {
                        store.remove(at: spec.key)
                    } else {
                        store.set(newValue, at: spec.key)
                    }
                    commit()
                }
            )) {
                Text("— default (\(defaultString.isEmpty ? "none" : defaultString)) —")
                    .tag(Self.defaultTag)
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .opacity(isPresent ? 1.0 : 0.6)
        }
    }
}

/// Filterable popover for `.choice` specs with many cases (e.g. the 74 chroma
/// highlight styles): a button showing the current/default value opens a
/// popover with a local-`@State` filter `TextField` over a scrollable list.
/// The filter text never touches the store — it's pure display filtering,
/// so it can't violate the per-keystroke invalidation contract even though
/// it re-renders per keystroke (this view is already the observation leaf).
private struct ConfigSearchableChoiceFieldRow: View {
    let spec: ConfigSettingSpec
    let options: [String]
    let store: ConfigValueStore
    let commit: () -> Void

    @State private var isPresented = false
    @State private var filterText = ""

    private var defaultString: String { spec.defaultValue.stringValue ?? "" }
    private var isPresent: Bool { store.isPresent(spec.key) }
    private var current: String { store.stringValue(spec.key) ?? defaultString }

    private var filteredOptions: [String] {
        let trimmed = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return options }
        return options.filter { $0.lowercased().contains(trimmed) }
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 4) {
                Text(isPresent ? current : "default (\(defaultString.isEmpty ? "none" : defaultString))")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(isPresent ? 1.0 : 0.6)
        .popover(isPresented: $isPresented) {
            searchableList
        }
        .onChange(of: isPresented) { _, presented in
            if !presented { filterText = "" }
        }
    }

    private var searchableList: some View {
        VStack(spacing: 0) {
            TextField("Search…", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .padding(8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    optionRow(
                        label: "— default (\(defaultString.isEmpty ? "none" : defaultString)) —",
                        isSelected: !isPresent,
                        dimmed: true
                    ) {
                        store.remove(at: spec.key)
                        commit()
                        isPresented = false
                    }

                    ForEach(filteredOptions, id: \.self) { option in
                        optionRow(label: option, isSelected: isPresent && current == option, dimmed: false) {
                            store.set(option, at: spec.key)
                            commit()
                            isPresented = false
                        }
                    }

                    if filteredOptions.isEmpty {
                        Text("No matches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(10)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .frame(width: 260)
    }

    private func optionRow(label: String, isSelected: Bool, dimmed: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .foregroundStyle(dimmed ? .secondary : .primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.15) : .clear)
    }
}

// MARK: - boolOrEnum

/// Store-value ↔ picker-selection mapping for `.boolOrEnum` fields
/// (`markup.highlight.lineNos`: `false`/`true`/`"inline"`/`"table"`).
/// Pure and side-effect-free so it's directly unit-testable without a
/// `ConfigValueStore`/view in scope (CONFIG-SCHEMA-SPEC §2.6, task brief's
/// "extract testable" instruction).
enum ConfigBoolOrEnumSelection: Equatable {
    case off
    case on
    case enumCase(String)
}

enum ConfigBoolOrEnumMapping {
    /// Maps a raw stored value to a selection. `nil` in ⇒ `nil` out (caller
    /// falls back to the schema default). Lenient like `ConfigValueStore`'s
    /// other typed reads: accepts `Bool`, a recognized enum-case `String`,
    /// `"true"`/`"false"` `String`, or `0`/`1` `Int`. Any other shape (e.g.
    /// an unrecognized string) maps to `nil` rather than guessing.
    static func selection(for rawValue: Any?, options: [String]) -> ConfigBoolOrEnumSelection? {
        guard let rawValue else { return nil }
        if let bool = rawValue as? Bool { return bool ? .on : .off }
        if let string = rawValue as? String {
            if options.contains(string) { return .enumCase(string) }
            switch string.lowercased() {
            case "true": return .on
            case "false": return .off
            default: return nil
            }
        }
        if let int = rawValue as? Int {
            if int == 0 { return .off }
            if int == 1 { return .on }
        }
        return nil
    }

    /// Maps a selection to the canonical Swift type written to the store:
    /// `Bool` for off/on, `String` for an enum case (CONFIG-SCHEMA-SPEC
    /// §2.3's "Store representation: false/true as Bool, enum case as
    /// String").
    static func storeValue(for selection: ConfigBoolOrEnumSelection) -> Any {
        switch selection {
        case .off: return false
        case .on: return true
        case .enumCase(let value): return value
        }
    }
}

private struct ConfigBoolOrEnumFieldRow: View {
    let spec: ConfigSettingSpec
    let options: [String]
    let store: ConfigValueStore
    let commit: () -> Void

    private static let defaultTag = "__default__"
    private static let offTag = "__off__"
    private static let onTag = "__on__"

    private var isPresent: Bool { store.isPresent(spec.key) }
    private var defaultIsOn: Bool { spec.defaultValue.boolValue ?? false }

    private var currentSelection: ConfigBoolOrEnumSelection {
        ConfigBoolOrEnumMapping.selection(for: store.value(at: spec.key), options: options)
            ?? (defaultIsOn ? .on : .off)
    }

    private func tag(for selection: ConfigBoolOrEnumSelection) -> String {
        switch selection {
        case .off: return Self.offTag
        case .on: return Self.onTag
        case .enumCase(let value): return value
        }
    }

    private func selection(forTag tag: String) -> ConfigBoolOrEnumSelection {
        switch tag {
        case Self.offTag: return .off
        case Self.onTag: return .on
        default: return .enumCase(tag)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: Binding(
                get: { isPresent ? tag(for: currentSelection) : Self.defaultTag },
                set: { newTag in
                    if newTag == Self.defaultTag {
                        store.remove(at: spec.key)
                    } else {
                        store.set(ConfigBoolOrEnumMapping.storeValue(for: selection(forTag: newTag)), at: spec.key)
                    }
                    commit()
                }
            )) {
                Text("— default (\(defaultIsOn ? "On" : "Off")) —")
                    .tag(Self.defaultTag)
                Text("Off").tag(Self.offTag)
                Text("On").tag(Self.onTag)
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .opacity(isPresent ? 1.0 : 0.6)
        }
    }
}

// MARK: - Text-like draft-commit types (string, duration, stringOrStringArray)

/// Local `@State` draft, committed to the store on blur/submit only — never
/// per keystroke. Generalizes `ConfigContentTab.PermalinkRowView`.
private struct ConfigTextDraftRow: View {
    let spec: ConfigSettingSpec
    let store: ConfigValueStore
    let commit: () -> Void
    /// Current stored value as display text, or `nil` if absent.
    let displayText: (ConfigValueStore) -> String?
    /// Prompt shown when absent (the schema default's textual form).
    let placeholderText: String
    /// Writes a non-empty, trimmed, changed value back to the store.
    let write: (String, ConfigValueStore) -> Void
    var trailingHint: String?
    var monospaced: Bool = false

    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    private var isPresent: Bool { store.isPresent(spec.key) }
    private var storedText: String { displayText(store) ?? "" }

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $draft, prompt: Text(placeholderText))
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .focused($isFocused)
                .onSubmit { commitDraft() }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commitDraft() }
                }

            if let trailingHint {
                Text(trailingHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !isPresent {
                DefaultValueTag()
            }
        }
        .onAppear { draft = isPresent ? storedText : "" }
        .onChange(of: storedText) { _, newValue in
            // External change (reset button, deprecation rename) while not
            // focused: resync the draft. Never overwrite live typing.
            if !isFocused { draft = isPresent ? newValue : "" }
        }
    }

    private func commitDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if isPresent {
                store.remove(at: spec.key)
                commit()
            }
            return
        }
        guard trimmed != (isPresent ? storedText : nil) else { return }
        write(trimmed, store)
        commit()
    }
}

// MARK: - int

private struct ConfigIntFieldRow: View {
    let spec: ConfigSettingSpec
    let store: ConfigValueStore
    let commit: () -> Void

    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    private var defaultInt: Int { spec.defaultValue.intValue ?? 0 }
    private var sentinelMeaning: String? { spec.defaultValue.sentinelMeaning }
    private var isPresent: Bool { store.isPresent(spec.key) }
    private var storedInt: Int? { store.intValue(spec.key) }

    private var placeholderText: String {
        sentinelMeaning ?? String(defaultInt)
    }

    /// Non-nil only when the value *currently shown* (present or default)
    /// equals the sentinel number — its meaning must render, the number
    /// must not (CONFIG-SCHEMA-SPEC §2.3/§2.6).
    private var activeSentinelCaption: String? {
        guard let sentinelMeaning else { return nil }
        let shown = isPresent ? storedInt : defaultInt
        guard let shown, shown == defaultInt else { return nil }
        return "→ \(sentinelMeaning)"
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 6) {
                TextField("", text: $draft, prompt: Text(placeholderText))
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .frame(width: 100)
                    .focused($isFocused)
                    .onSubmit { commitDraft() }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commitDraft() }
                    }

                if !isPresent {
                    DefaultValueTag()
                }
            }
            if let activeSentinelCaption {
                Text(activeSentinelCaption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear { draft = isPresent ? String(storedInt ?? defaultInt) : "" }
        .onChange(of: storedInt) { _, newValue in
            if !isFocused {
                draft = isPresent ? String(newValue ?? defaultInt) : ""
            }
        }
    }

    private func commitDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            if isPresent {
                store.remove(at: spec.key)
                commit()
            }
            return
        }
        guard let value = Int(trimmed) else {
            // Not parseable: revert rather than write garbage.
            draft = isPresent ? String(storedInt ?? defaultInt) : ""
            return
        }
        guard value != storedInt else { return }
        store.set(value, at: spec.key)
        commit()
    }
}

// MARK: - double

private struct ConfigDoubleFieldRow: View {
    let spec: ConfigSettingSpec
    let store: ConfigValueStore
    let commit: () -> Void

    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    private var defaultDouble: Double { spec.defaultValue.doubleValue ?? 0 }
    private var sentinelMeaning: String? { spec.defaultValue.sentinelMeaning }
    private var isPresent: Bool { store.isPresent(spec.key) }
    private var storedDouble: Double? { store.doubleValue(spec.key) }

    private var placeholderText: String {
        sentinelMeaning ?? formatted(defaultDouble)
    }

    private var activeSentinelCaption: String? {
        guard let sentinelMeaning else { return nil }
        let shown = isPresent ? storedDouble : defaultDouble
        guard let shown, shown == defaultDouble else { return nil }
        return "→ \(sentinelMeaning)"
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 6) {
                TextField("", text: $draft, prompt: Text(placeholderText))
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .frame(width: 100)
                    .focused($isFocused)
                    .onSubmit { commitDraft() }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commitDraft() }
                    }

                if !isPresent {
                    DefaultValueTag()
                }
            }
            if let activeSentinelCaption {
                Text(activeSentinelCaption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear { draft = isPresent ? formatted(storedDouble ?? defaultDouble) : "" }
        .onChange(of: storedDouble) { _, newValue in
            if !isFocused {
                draft = isPresent ? formatted(newValue ?? defaultDouble) : ""
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }

    private func commitDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            if isPresent {
                store.remove(at: spec.key)
                commit()
            }
            return
        }
        guard let value = Double(trimmed) else {
            draft = isPresent ? formatted(storedDouble ?? defaultDouble) : ""
            return
        }
        guard value != storedDouble else { return }
        store.set(value, at: spec.key)
        commit()
    }
}

// MARK: - stringArray

private struct ConfigStringArrayFieldRow: View {
    let spec: ConfigSettingSpec
    let store: ConfigValueStore
    let commit: () -> Void

    @State private var newToken: String = ""

    private var defaultArray: [String] { spec.defaultValue.stringArrayValue ?? [] }
    private var isPresent: Bool { store.isPresent(spec.key) }
    private var current: [String] { store.stringArrayValue(spec.key) ?? [] }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if current.isEmpty {
                HStack(spacing: 6) {
                    Text(defaultArray.isEmpty ? "—" : defaultArray.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !isPresent {
                        DefaultValueTag()
                    }
                }
            } else {
                // Simple wrapping chip row; the taxonomies-tab pair editor
                // stays the richer pattern for its own bespoke section.
                HStack(spacing: 4) {
                    ForEach(current, id: \.self) { token in
                        HStack(spacing: 2) {
                            Text(token).font(.caption)
                            Button {
                                removeToken(token)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(token)")
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(Capsule())
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("add…", text: $newToken)
                    .frame(width: 120)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor))
                    .onSubmit { addToken() }
                Button("Add") { addToken() }
                    .disabled(newToken.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addToken() {
        let trimmed = newToken.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var array = current
        array.append(trimmed)
        store.set(array, at: spec.key)
        commit()
        newToken = ""
    }

    private func removeToken(_ token: String) {
        var array = current
        array.removeAll { $0 == token }
        if array.isEmpty {
            store.remove(at: spec.key)
        } else {
            store.set(array, at: spec.key)
        }
        commit()
    }
}

// MARK: - Later-phase fallback

/// Placeholder for `ConfigValueType`s no tab wires up yet in Phase 1d
/// (`boolOrEnum`, `boolOrSectionMap`, `dictionary`, `stringMap`, `rawOnly`).
/// Read-only by design — each gets its own dedicated control in a later
/// phase (§2.6); this row exists purely so `ConfigFieldView` degrades
/// safely rather than crashing if one of these specs is ever passed to it
/// early.
private struct ConfigComingLaterRow: View {
    let spec: ConfigSettingSpec

    var body: some View {
        Text(spec.type.isRawOnly ? "Edit in Raw" : "Coming in a later phase — edit in Raw for now")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private extension ConfigValueType {
    var isRawOnly: Bool {
        if case .rawOnly = self { return true }
        return false
    }
}
