import Foundation

/// One finding from `ConfigLintCatalog.scan` (CONFIG-SCHEMA-SPEC §2.5,
/// mechanism 2: "removed-key lint table") — a key Hugo no longer reads at
/// all, found present in the file. Distinct from `ConfigDeprecation`
/// (mechanism 1): these keys don't have a `ConfigSettingSpec` row of their
/// own to badge, so they surface as a warnings section instead.
struct ConfigLintWarning: Equatable, Identifiable {
    var id: String { key + "|" + message }
    /// The offending key path (e.g. `"paginate"`, `"permalinks.posts"`).
    let key: String
    let message: String
    /// Set only when the fix is a pure rename (`remove(old); set(value, at: new)`)
    /// the UI can offer as a one-click "Use <new key>" button — per the task
    /// brief, that's `paginate`/`paginatePath` only. The root
    /// `googleAnalytics`/`disqusShortname` fallbacks and the permalink token
    /// warnings are explanatory-only (`nil`).
    let replacementKey: String?
}

/// Scans a `ConfigValueStore` for keys Hugo no longer reads (CONFIG-SCHEMA-SPEC
/// §2.5 mechanism 2, §1.2 "Legacy root keys still honored as fallbacks" /
/// "Root paginate/paginatePath were removed"). Pure over the store's read
/// API — no view dependency — so `scan` is directly unit-testable.
enum ConfigLintCatalog {
    /// A removed/relocated root key and its replacement.
    struct RemovedKeyEntry {
        let key: String
        let replacementKey: String
        let message: String
        /// True for `paginate`/`paginatePath`: the value moves to the new key
        /// unchanged, so a one-click rename is safe. False for the
        /// `googleAnalytics`/`disqusShortname` root fallbacks: Hugo still
        /// reads them (this is "legacy location", not "removed"), and moving
        /// the value could collide with an already-set nested value, so no
        /// auto-fix button is offered — explanatory text only.
        let renameIsPure: Bool
    }

    static let removedRootKeys: [RemovedKeyEntry] = [
        RemovedKeyEntry(
            key: "paginate",
            replacementKey: "pagination.pagerSize",
            message: "paginate was removed in favor of pagination.pagerSize.",
            renameIsPure: true
        ),
        RemovedKeyEntry(
            key: "paginatePath",
            replacementKey: "pagination.path",
            message: "paginatePath was removed in favor of pagination.path.",
            renameIsPure: true
        ),
        RemovedKeyEntry(
            key: "googleAnalytics",
            replacementKey: "services.googleAnalytics.ID",
            message: "googleAnalytics at the root is a legacy location — Hugo still reads it as a fallback, but services.googleAnalytics.ID is preferred.",
            renameIsPure: false
        ),
        RemovedKeyEntry(
            key: "disqusShortname",
            replacementKey: "services.disqus.shortname",
            message: "disqusShortname at the root is a legacy location — Hugo still reads it as a fallback, but services.disqus.shortname is preferred.",
            renameIsPure: false
        )
    ]

    /// Permalink tokens deprecated in Hugo v0.144 (finding #9), keyed to
    /// their replacement token for the warning text.
    static let deprecatedPermalinkTokens: [String: String] = [
        ":filename": ":contentbasename",
        ":slugorfilename": ":slugorcontentbasename"
    ]

    /// Full scan: removed root keys present in the file, plus deprecated
    /// permalink tokens found inside `permalinks` values (not keys).
    static func scan(store: ConfigValueStore) -> [ConfigLintWarning] {
        var warnings: [ConfigLintWarning] = []
        for entry in removedRootKeys where store.isPresent(entry.key) {
            warnings.append(ConfigLintWarning(
                key: entry.key,
                message: entry.message,
                replacementKey: entry.renameIsPure ? entry.replacementKey : nil
            ))
        }
        warnings.append(contentsOf: scanPermalinkTokens(store: store))
        return warnings
    }

    /// Scans every permalink pattern value (flat `[section: pattern]` shape,
    /// or the nested `permalinks.page.<section>` shape Hugo also accepts) for
    /// a deprecated token substring.
    private static func scanPermalinkTokens(store: ConfigValueStore) -> [ConfigLintWarning] {
        guard let raw = store.value(at: "permalinks") else { return [] }

        var patterns: [(label: String, pattern: String)] = []
        if let flat = raw as? [String: String] {
            patterns = flat.map { (label: $0.key, pattern: $0.value) }
        } else if let nested = raw as? [String: Any] {
            for (section, value) in nested {
                if let pattern = value as? String {
                    patterns.append((label: section, pattern: pattern))
                } else if let subMap = value as? [String: String] {
                    for (sub, pattern) in subMap {
                        patterns.append((label: "\(section).\(sub)", pattern: pattern))
                    }
                }
            }
        }

        var warnings: [ConfigLintWarning] = []
        for (label, pattern) in patterns.sorted(by: { $0.label < $1.label }) {
            for (deprecatedToken, replacementToken) in deprecatedPermalinkTokens.sorted(by: { $0.key < $1.key })
            where pattern.contains(deprecatedToken) {
                warnings.append(ConfigLintWarning(
                    key: "permalinks.\(label)",
                    message: "permalinks.\(label) uses deprecated token \(deprecatedToken); use \(replacementToken) instead.",
                    replacementKey: nil
                ))
            }
        }
        return warnings
    }
}
