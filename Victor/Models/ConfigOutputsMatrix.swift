import Foundation

/// Pure state/logic for the Integrations tab's outputs matrix (CONFIG-SCHEMA-SPEC §3.6).
/// No store or view dependency, so read shape, toggle transitions and write-back are
/// directly unit-testable.
///
/// Casing: existing entries keep whatever the file used (matched case-insensitively,
/// never rewritten); newly-checked formats use the §4.4 canonical spelling.
enum ConfigOutputsMatrix {
    /// Matrix rows (CONFIG-SCHEMA-SPEC §3.6: "rows = home/section/taxonomy/term/page").
    static let kinds: [String] = ["home", "section", "taxonomy", "term", "page"]

    /// §4.4 default `outputs` per kind — shown dimmed when a kind's key is
    /// absent from the file entirely.
    static let defaultOutputs: [String: [String]] = [
        "home": ["html", "rss"],
        "section": ["html", "rss"],
        "taxonomy": ["html", "rss"],
        "term": ["html", "rss"],
        "page": ["html"]
    ]

    /// Checkbox columns: §4.4 built-in format names (canonical lowercase
    /// spelling) followed by any keys from the user's own `outputFormats`
    /// section, de-duplicated case-insensitively (built-ins win the slot on a
    /// collision — a user redefining e.g. `HTML` in `outputFormats` doesn't
    /// get a second column).
    static func columns(customFormatKeys: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in ConfigSchema.outputFormatNames where seen.insert(name.lowercased()).inserted {
            result.append(name)
        }
        for name in customFormatKeys where seen.insert(name.lowercased()).inserted {
            result.append(name)
        }
        return result
    }

    /// Converts a raw `outputs` subtree (`[String: Any]`, values possibly
    /// `[String]` or `[Any]` of strings depending on parse path) into a
    /// uniform `[String: [String]]`. Unrecognized value shapes are dropped
    /// rather than guessed at.
    static func normalizedOutputs(from raw: [String: Any]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for (key, value) in raw {
            if let array = value as? [String] {
                result[key] = array
            } else if let array = value as? [Any] {
                let strings = array.compactMap { $0 as? String }
                if strings.count == array.count { result[key] = strings }
            } else if let single = value as? String {
                result[key] = [single]
            }
        }
        return result
    }

    /// The formats checked for one row, and whether the kind's key is
    /// actually present (vs. falling back to the §4.4 default — the view
    /// dims the row in that case).
    static func checkedFormats(for kind: String, outputs: [String: [String]]) -> (formats: [String], isPresent: Bool) {
        if let stored = outputs[kind] {
            return (stored, true)
        }
        return (defaultOutputs[kind] ?? [], false)
    }

    /// The array `kind` should hold after toggling `format`. Toggling any cell on an
    /// absent/default row materializes the full default set plus the new format.
    /// Case-insensitive match/removal. Returns `nil` when the result would be empty -
    /// the caller then removes the key rather than writing `[]`.
    static func toggling(format: String, newState isOn: Bool, currentlyChecked: [String]) -> [String]? {
        var result = currentlyChecked
        if isOn {
            if !result.contains(where: { $0.caseInsensitiveCompare(format) == .orderedSame }) {
                result.append(format)
            }
        } else {
            result.removeAll { $0.caseInsensitiveCompare(format) == .orderedSame }
        }
        return result.isEmpty ? nil : result
    }

    /// Applies one checkbox toggle to the full outputs dict (all kinds, not
    /// just the 5 matrix rows — any other kind key already in the file, e.g.
    /// a temporary kind the matrix doesn't render, passes through untouched).
    /// Empty-array-after-toggle removes that kind's key (never writes `[]`).
    static func applyToggle(kind: String, format: String, isOn: Bool, in outputs: [String: [String]]) -> [String: [String]] {
        var result = outputs
        let baseline = result[kind] ?? defaultOutputs[kind] ?? []
        if let newArray = toggling(format: format, newState: isOn, currentlyChecked: baseline) {
            result[kind] = newArray
        } else {
            result.removeValue(forKey: kind)
        }
        return result
    }

    /// Converts a `[String: [String]]` outputs dict to the `Any`-typed shape
    /// `ConfigValueStore.replaceSubtree` expects, or `nil` when the dict is
    /// empty — the caller should `store.remove(at: "outputs")` entirely in
    /// that case rather than write an empty table/object ("empty outputs →
    /// remove outputs").
    static func storageValue(for outputs: [String: [String]]) -> [String: Any]? {
        outputs.isEmpty ? nil : outputs.mapValues { $0 as Any }
    }
}
