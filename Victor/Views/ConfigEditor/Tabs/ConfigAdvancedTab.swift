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
    ///   - rootKey: a top-level key from `ConfigValueStore.orderedRootKeys`,
    ///     in whatever case the source file used.
    ///   - schemaKeys: every `ConfigSettingSpec.key` (dotted paths), e.g.
    ///     `ConfigSchema.all.map(\.key)`.
    ///   - rawOnlySectionKeys: `ConfigSchema.rawOnlySectionKeys`. Matched
    ///     case-insensitively: the schema spells these lowercase
    ///     ("mediatypes", "outputformats", "contenttypes", "httpcache") but
    ///     real Hugo files use camelCase ("mediaTypes", "outputFormats",
    ///     "httpCache"), and `ConfigValueStore` lookups are otherwise
    ///     case-sensitive.
    ///   - bespokeRootKeys: defaults to `Self.bespokeRootKeys`; parameterized
    ///     for testability.
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

/// Advanced tab for Hugo configuration editor (CONFIG-SCHEMA-SPEC §3.7,
/// design doc §3.2). Three sections plus a read-only raw-only list:
///
/// (a) **Site Params** — recursive editor over `store.subtree("params")`.
/// (b) **All Settings** — searchable flat list of every `.advanced`-group
///     schema entry (skipping `.rawOnly`-typed ones) plus every schema entry
///     not rendered on Essentials/Content/Taxonomies today.
/// (c) **Unknown keys** — root keys the classifier above calls `.unknown`:
///     recursive editor per key, same family as (a).
/// Plus a read-only list of `.rawOnly` sections that are actually present in
/// the file, each with an "Edit in Raw" button.
///
/// Typing-latency (CLAUDE.md contract, CONFIG-SCHEMA-SPEC §2.8): this body
/// reads `config.store.version` once, at the top — an explicitly-sanctioned
/// exception (task brief / spec §2.8) because it drives which *rows exist*
/// (unknown-keys list, present-rawOnly list), not per-keystroke content, and
/// only changes on a committed edit (recursive editors below commit on
/// blur/toggle/add/remove, never per keystroke — see
/// `Views/Components/RecursiveValueEditor.swift`). All Settings' own text
/// filter is separate `@State` confined to that section's view.
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

    /// Schema keys already rendered by `ConfigEssentialsTab`/
    /// `ConfigContentTab`/`ConfigTaxonomiesTab`/`ConfigMarkupTab` today (read
    /// directly off those views' source, not the design doc's aspirational
    /// full-tab lists — several `.essentials`/`.contentBuild`/
    /// `.urlsTaxonomies`-group entries aren't wired up on their tab yet and
    /// so correctly surface in All Settings (b) below instead of going
    /// missing). `taxonomies` has a schema entry but is rendered by
    /// `ConfigTaxonomiesTab`'s bespoke editor, not `ConfigFieldView` — still
    /// "rendered elsewhere". `ConfigMarkupTab.allRenderedKeys` (§3.5's
    /// main-table 26 keys) is pulled from that tab's own source rather than
    /// re-listed here, so the two can't drift.
    private static let renderedOnOtherTabs: Set<String> = ([
        "baseURL", "title", "languageCode", "theme", "copyright",
        "buildDrafts", "buildFuture", "buildExpired", "enableRobotsTXT", "summaryLength",
        "taxonomies"
    ] as Set<String>).union(ConfigMarkupTab.allRenderedKeys)

    var body: some View {
        let _ = config.store.version // §2.8 exception — see header doc.

        Form {
            siteParamsSection
            allSettingsSection
            unknownKeysSection
            rawOnlySectionsList
        }
        .formStyle(.grouped)
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
            AllSettingsListView(
                store: config.store,
                context: validationContext,
                excludedKeys: Self.renderedOnOtherTabs
            )
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
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.label)
                            Text("\(section.count) key\(section.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit in Raw") { switchToRaw() }
                            .buttonStyle(.borderless)
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

/// Searchable flat list of every schema entry not shown on another tab.
/// Isolated into its own view so its `@State searchText` doesn't sit in
/// `ConfigAdvancedTab`'s body (keeps the per-keystroke read of `searchText`
/// scoped to exactly the rows it filters, matching the leaf-observation
/// pattern used throughout this tab).
///
/// No explicit `LazyVStack`/`List` wrapper: `Form` on macOS is itself
/// `List`-backed, and a `ForEach` placed directly in a `Section` gets that
/// `List`'s per-row virtualization for free — wrapping it in a second lazy
/// container here would nest one scrolling/virtualizing construct inside
/// another for no benefit and fight `Form`'s own row styling.
private struct AllSettingsListView: View {
    let store: ConfigValueStore
    let context: ValidationContext
    let excludedKeys: Set<String>

    @State private var searchText = ""

    /// `.advanced`-group entries (minus `.rawOnly`-typed ones, which get
    /// their own read-only list) plus anything from another group that
    /// isn't rendered on that group's tab yet (markup/integrations have no
    /// tab at all pre-Phase-4/5; several essentials/contentBuild/
    /// urlsTaxonomies entries aren't wired up on their tab yet either).
    private var candidates: [ConfigSettingSpec] {
        ConfigSchema.all
            .filter { !excludedKeys.contains($0.key) }
            .filter { spec in
                if case .rawOnly = spec.type { return false }
                if spec.group == .menus { return false } // no schema entries anyway
                return true
            }
            .sorted { $0.label < $1.label }
    }

    private var filtered: [ConfigSettingSpec] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return candidates }
        return candidates.filter {
            $0.key.lowercased().contains(trimmed) || $0.label.lowercased().contains(trimmed)
        }
    }

    var body: some View {
        TextField("Search settings…", text: $searchText)
            .textFieldStyle(.roundedBorder)

        ForEach(filtered) { spec in
            ConfigFieldView(spec: spec, store: store, context: context)
        }
    }
}

// MARK: - (c) Unknown key row

private struct UnknownKeyEditorRow: View {
    let rootKey: String
    let store: ConfigValueStore
    let commit: () -> Void

    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            DataValueEditor(
                value: Binding(
                    get: { store.value(at: rootKey) ?? [String: Any]() },
                    set: { store.set($0, at: rootKey) }
                ),
                onChanged: commit
            )
            .padding(.leading, 16)
        } label: {
            HStack {
                Text(rootKey)
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Button(role: .destructive) {
                    store.remove(at: rootKey)
                    commit()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(rootKey)")
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
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
