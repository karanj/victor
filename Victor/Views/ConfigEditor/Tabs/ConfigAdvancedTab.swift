import SwiftUI

/// Root-level classification for the Advanced tab's key sorting (§3.7).
/// Pure enum, no view/store dependency, so `ConfigAdvancedKeyClassifier` is
/// directly unit-testable.
enum ConfigRootKeyClassification: Equatable {
    /// A `ConfigSettingSpec` key equals this root, or is a dotted path whose
    /// first segment equals this root (e.g. `"markup.goldmark.…"` makes
    /// root `"markup"` known even with no `"markup"`-exact entry).
    case known
    /// Matches one of `ConfigSchema.rawOnlySectionKeys`, case-insensitively.
    case rawOnly
    /// Materialized by its own dedicated, non-generic editor elsewhere in
    /// the app (Site Params section (a), taxonomies/permalinks/menus) —
    /// never schema-known, never "unknown" either.
    case bespoke
    /// None of the above: an arbitrary key the user (or a theme) put in the
    /// config file that Victor has no dedicated UI for. Section (c).
    case unknown
}

/// Classifies root-level Hugo config keys for the Advanced tab's three-way
/// split (CONFIG-SCHEMA-SPEC §3.7). A pure static function — no view, no
/// `ConfigValueStore` — so it's testable without a `ConfigEditorView` in
/// scope.
enum ConfigAdvancedKeyClassifier {
    /// Root keys with their own dedicated, non-generic editor elsewhere in
    /// the app. `menu` and `menus` both appear because the file may spell
    /// either one (`HugoConfig.menuKeySpelling`, CONFIG-SCHEMA-SPEC §2.7).
    static let bespokeRootKeys: Set<String> = ["params", "taxonomies", "permalinks", "menus", "menu"]

    /// - Parameters:
    ///   - rootKey: a top-level key from `ConfigValueStore.orderedRootKeys`
    ///   - schemaKeys: every `ConfigSettingSpec.key` (dotted paths)
    ///   - rawOnlySectionKeys: matched case-insensitively - the schema spells these
    ///     lowercase but real Hugo files use camelCase (`mediaTypes`, `outputFormats`)
    ///   - bespokeRootKeys: parameterized for testability
    static func classify(
        rootKey: String,
        schemaKeys: [String],
        rawOnlySectionKeys: [String],
        bespokeRootKeys: Set<String> = ConfigAdvancedKeyClassifier.bespokeRootKeys
    ) -> ConfigRootKeyClassification {
        if bespokeRootKeys.contains(rootKey) { return .bespoke }
        let loweredRoot = rootKey.lowercased()
        if rawOnlySectionKeys.contains(where: { $0.lowercased() == loweredRoot }) {
            return .rawOnly
        }
        if schemaKeys.contains(where: { $0 == rootKey || $0.hasPrefix(rootKey + ".") }) {
            return .known
        }
        return .unknown
    }
}

/// Advanced tab (CONFIG-SCHEMA-SPEC §3.7). Site Params, All Settings, Unknown Keys, plus
/// a read-only list of `.rawOnly` sections present in the file.
///
/// This body reads `store.version` once - a sanctioned exception to the per-keystroke
/// contract, since it drives which *rows exist*, not their content, and only changes on
/// a committed edit.
struct ConfigAdvancedTab: View {
    let config: HugoConfig

    @Environment(\.configCommitAction) private var commit
    @Environment(\.configSwitchToRawAction) private var switchToRaw

    /// No validator among the fields rendered here needs `siteURL` (the one
    /// validator that does, `themeExists`, is on `theme`, which renders on
    /// the Essentials tab, not here).
    private var validationContext: ValidationContext {
        ValidationContext(siteURL: nil, store: config.store)
    }

    /// Keys already rendered elsewhere, read off each tab's own `allRenderedKeys` rather
    /// than re-listed here so the two can't drift. `locale`/`languageCode` are excluded
    /// because Essentials' bespoke Locale row serves both.
    static let renderedOnOtherTabs: Set<String> = ([
        "baseURL", "title", "locale", "languageCode", "theme", "copyright", "timeZone",
        "buildDrafts", "buildFuture", "buildExpired", "summaryLength"
    ] as Set<String>)
        .union(ConfigMarkupTab.allRenderedKeys)
        .union(ConfigURLsTaxonomiesTab.allRenderedKeys)
        .union(ConfigIntegrationsTab.allRenderedKeys)

    var body: some View {
        let _ = config.store.version // §2.8 exception — see header doc.

        Form {
            legacyKeysSection
            siteParamsSection
            allSettingsSection
            unknownKeysSection
            rawOnlySectionsList
        }
        .formStyle(.grouped)
    }

    // MARK: - Legacy keys (CONFIG-SCHEMA-SPEC §2.5 mechanism 2)

    /// Removed-key lint findings. These keys have no `ConfigSettingSpec` row of their own -
    /// `paginate`/`paginatePath` were removed rather than deprecated, and permalink token
    /// warnings live inside a value - so they need their own section. Only the two pure
    /// renames get a one-click fix; the rest are explanatory.
    @ViewBuilder
    private var legacyKeysSection: some View {
        let warnings = ConfigLintCatalog.scan(store: config.store)
        if !warnings.isEmpty {
            Section {
                ForEach(warnings) { warning in
                    LabeledContent {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(warning.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let replacementKey = warning.replacementKey {
                                Button("Use \(replacementKey)") {
                                    guard let value = config.store.value(at: warning.key) else { return }
                                    config.store.remove(at: warning.key)
                                    config.store.set(value, at: replacementKey)
                                    commit()
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    } label: {
                        Label {
                            Text(warning.key)
                                .font(.system(.body, design: .monospaced))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.Status.warning)
                        }
                    }
                }
            } header: {
                Text("Legacy Keys")
            } footer: {
                Text("Keys Hugo no longer reads (or reads only as a fallback), found in this file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - (a) Site Params

    private var siteParamsSection: some View {
        Section {
            DataDictionaryEditor(
                data: Binding(
                    get: { config.store.subtree("params") ?? [:] },
                    set: { newValue in
                        if newValue.isEmpty {
                            config.store.remove(at: "params")
                        } else {
                            config.store.replaceSubtree("params", with: newValue)
                        }
                    }
                ),
                onChanged: { commit() }
            )
        } header: {
            Text("Site Params")
        } footer: {
            Text("Custom values available to templates as .Site.Params.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - (b) All Settings

    private var allSettingsSection: some View {
        Section {
            AllSettingsListView(store: config.store, context: validationContext)
        } header: {
            Text("All Settings")
        } footer: {
            Text("Every known Hugo setting not already shown on another tab. Defaults are shown dimmed and are never written unless changed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - (c) Unknown keys

    private var unknownRootKeys: [String] {
        let schemaKeys = ConfigSchema.all.map(\.key)
        let rawOnlyKeys = ConfigSchema.rawOnlySectionKeys
        return config.store.orderedRootKeys.filter { key in
            ConfigAdvancedKeyClassifier.classify(
                rootKey: key, schemaKeys: schemaKeys, rawOnlySectionKeys: rawOnlyKeys
            ) == .unknown
        }.sorted()
    }

    @ViewBuilder
    private var unknownKeysSection: some View {
        let keys = unknownRootKeys
        if !keys.isEmpty {
            Section {
                ForEach(keys, id: \.self) { key in
                    UnknownKeyEditorRow(rootKey: key, store: config.store, commit: commit)
                }
            } header: {
                Text("Unknown Keys")
            } footer: {
                Text("Keys found in the file that match no known Hugo setting. Preserved and editable, not validated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Raw-only sections present in the file

    private var presentRawOnlySections: [(key: String, label: String, help: String, count: Int)] {
        let rootKeys = config.store.orderedRootKeys
        return ConfigSchema.rawOnlySections.compactMap { section in
            guard let actualKey = rootKeys.first(where: { $0.lowercased() == section.key.lowercased() }) else {
                return nil
            }
            let count = config.store.subtree(actualKey)?.count ?? 0
            return (key: actualKey, label: section.label, help: section.help, count: count)
        }
    }

    @ViewBuilder
    private var rawOnlySectionsList: some View {
        let sections = presentRawOnlySections
        if !sections.isEmpty {
            Section {
                ForEach(sections, id: \.key) { section in
                    LabeledContent {
                        HStack(spacing: 6) {
                            Text("\(section.count) key\(section.count == 1 ? "" : "s")")
                                .countBadgeStyle()
                            Button("Edit in Raw") { switchToRaw() }
                                .buttonStyle(.borderless)
                        }
                    } label: {
                        Text(section.label)
                    }
                    .help(section.help)
                }
            } header: {
                Text("Raw-Only Sections")
            } footer: {
                Text("Hugo settings complex enough that Victor doesn't offer a form editor for them yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - (b) All Settings list

/// Searchable flat list of every schema entry not shown on another tab. Its own view so
/// `searchText` stays scoped to the rows it filters.
///
/// Rows are gated behind a filter or an explicit "show all": a grouped `Form` builds
/// every row up front, and all 126 cost 611 ms of the ~690 ms tab switch. `LazyVStack`
/// fixes the cost but loses Form's row styling; `List` loses the shared label column.
private struct AllSettingsListView: View {
    let store: ConfigValueStore
    let context: ValidationContext

    @State private var searchText = ""
    @State private var showAll = false

    /// `.advanced`-group entries (minus `.rawOnly`-typed ones, which get
    /// their own read-only list) plus anything from another group that
    /// isn't rendered on that group's tab yet. Computed once: it depends
    /// only on statics, and as a computed property it re-filtered and
    /// re-sorted all 222 specs on every keystroke in the filter field.
    static let candidates: [ConfigSettingSpec] = ConfigSchema.all
        .filter { !ConfigAdvancedTab.renderedOnOtherTabs.contains($0.key) }
        .filter { spec in
            if case .rawOnly = spec.type { return false }
            if spec.group == .menus { return false } // no schema entries anyway
            return true
        }
        .sorted { $0.label < $1.label }

    private var filtered: [ConfigSettingSpec] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return Self.candidates }
        return Self.candidates.filter {
            $0.key.lowercased().contains(trimmed) || $0.label.lowercased().contains(trimmed)
        }
    }

    /// Rows to build this pass: matches while filtering, everything once
    /// the user asks for it, nothing otherwise.
    private var visibleRows: [ConfigSettingSpec] {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return filtered }
        return showAll ? Self.candidates : []
    }

    var body: some View {
        let rows = visibleRows

        LabeledContent("Filter") {
            HStack(spacing: 6) {
                TextField("", text: $searchText, prompt: Text("Name or key"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: AppConstants.FormField.textWidth)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear Filter")
                }
                if !searchText.isEmpty {
                    Text("\(rows.count) of \(Self.candidates.count)")
                        .countBadgeStyle()
                }
            }
        }

        if rows.isEmpty && !showAll {
            LabeledContent("Browse") {
                Button("Show all \(Self.candidates.count) settings") { showAll = true }
            }
        }

        ForEach(rows) { spec in
            ConfigFieldView(spec: spec, store: store, context: context)
        }
    }
}

// MARK: - (c) Unknown key row

/// An unknown root key is a dictionary entry whose dictionary is the store
/// root, so it reuses `DataFieldRow` rather than restating the layout.
private struct UnknownKeyEditorRow: View {
    let rootKey: String
    let store: ConfigValueStore
    let commit: () -> Void

    var body: some View {
        DataFieldRow(
            key: rootKey,
            value: Binding(
                get: { store.value(at: rootKey) ?? [String: Any]() },
                set: { newValue in
                    store.set(newValue, at: rootKey)
                    commit()
                }
            ),
            onDelete: {
                store.remove(at: rootKey)
                commit()
            }
        )
    }
}

// MARK: - Environment: switch-to-raw action

/// How the Advanced tab's "Edit in Raw" button (raw-only sections list)
/// reaches `ConfigEditorView`'s `showRawEditor` toggle. Same "one action,
/// many leaves" shape as `configCommitAction` (`ConfigFieldView.swift`):
/// `ConfigEditorView` sets it once around the `TabView`, `ConfigAdvancedTab`
/// never reaches for `ConfigEditorView` state directly.
private struct ConfigSwitchToRawActionKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var configSwitchToRawAction: () -> Void {
        get { self[ConfigSwitchToRawActionKey.self] }
        set { self[ConfigSwitchToRawActionKey.self] = newValue }
    }
}
