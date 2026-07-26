import Foundation

/// Context a `ConfigValidator` runs with — cross-field and filesystem lookups
/// some validators need (e.g. `themeExists` reading the `themes/` directory,
/// `outputFormatsKnown` reading the user's custom `outputFormats` section).
/// CONFIG-SCHEMA-SPEC §2.4.
struct ValidationContext {
    /// The site root, for filesystem-relative lookups (e.g. `themes/<name>`).
    /// `nil` when no site is open (tests, or a config with no known root).
    let siteURL: URL?
    /// The config's value store, for cross-field checks.
    let store: ConfigValueStore
}

/// A single-field validator. All validators in the catalog below return
/// **warnings, never blocking errors** (CONFIG-SCHEMA-SPEC §2.4/design doc
/// §3.3): a `nil` result means "no complaint", any non-nil `String` is
/// warning text to show next to the field. Nothing here prevents a save.
struct ConfigValidator: Sendable {
    /// `Any` is deliberately unconstrained: the field's raw stored value
    /// (Bool/String/Int/Double/[String]/[String:String]/...) is handed
    /// straight through, matching `ConfigValueStore`'s "lenient reads" values.
    let validate: @Sendable (Any, ValidationContext) -> String?
}

/// The validator catalog (CONFIG-SCHEMA-SPEC §2.4). One property/function
/// per row of the table; `ConfigSchema` wires these onto the relevant
/// `ConfigSettingSpec` entries.
enum ConfigValidators {

    // MARK: - baseURL

    /// Parses as a URL with scheme + host; warns (doesn't block) when there's
    /// no trailing slash, since Hugo's own docs recommend one.
    static let absoluteURL = ConfigValidator { value, _ in
        guard let string = value as? String, !string.isEmpty else { return nil }
        guard let url = URL(string: string),
              let scheme = url.scheme, !scheme.isEmpty,
              let host = url.host, !host.isEmpty else {
            return "Not a valid absolute URL — needs a scheme and host (e.g. https://example.com/)."
        }
        if !string.hasSuffix("/") {
            return "baseURL usually ends with a trailing slash."
        }
        return nil
    }

    // MARK: - locale / defaultContentLanguage

    /// Lenient `xx` / `xx-YY` shape check — not a BCP 47 registry lookup.
    static let bcp47ish = ConfigValidator { value, _ in
        guard let string = value as? String, !string.isEmpty else { return nil }
        let pattern = "^[a-zA-Z]{2,3}(-[a-zA-Z0-9]{2,8})*$"
        if string.range(of: pattern, options: .regularExpression) == nil {
            return "\"\(string)\" doesn't look like a language tag (expected xx or xx-YY)."
        }
        return nil
    }

    // MARK: - timeZone

    /// Member of `TimeZone.knownTimeZoneIdentifiers` — also powers the picker.
    static let timezone = ConfigValidator { value, _ in
        guard let string = value as? String, !string.isEmpty else { return nil }
        if !TimeZone.knownTimeZoneIdentifiers.contains(string) {
            return "\"\(string)\" is not a known IANA time zone identifier."
        }
        return nil
    }

    // MARK: - theme

    /// Each name should be a directory under `themes/`. Skipped (info, not a
    /// warning — returns `nil`) when a `module` section is present, since
    /// module-provided themes aren't on disk under `themes/`.
    static let themeExists = ConfigValidator { value, context in
        guard !context.store.isPresent("module") else { return nil }
        guard let siteURL = context.siteURL else { return nil }

        let names: [String]
        if let array = value as? [String] { names = array } else if let string = value as? String { names = [string] } else { return nil }

        let themesDir = siteURL.appendingPathComponent("themes")
        var missing: [String] = []
        for name in names {
            var isDirectory: ObjCBool = false
            let path = themesDir.appendingPathComponent(name).path
            if !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) || !isDirectory.boolValue {
                missing.append(name)
            }
        }
        guard !missing.isEmpty else { return nil }
        return "Theme(s) not found in themes/: \(missing.joined(separator: ", "))."
    }

    // MARK: - Numeric ranges

    /// Bounds check, accepting the same lenient shapes `ConfigValueStore.intValue` does.
    static func intRange(min: Int? = nil, max: Int? = nil) -> ConfigValidator {
        ConfigValidator { value, _ in
            let intValue: Int?
            if let i = value as? Int {
                intValue = i
            } else if let d = value as? Double, d.truncatingRemainder(dividingBy: 1) == 0 {
                intValue = Int(d)
            } else if let s = value as? String {
                intValue = Int(s)
            } else {
                intValue = nil
            }
            guard let intValue else { return "Expected a whole number." }
            if let min, intValue < min { return "Must be \u{2265} \(min)." }
            if let max, intValue > max { return "Must be \u{2264} \(max)." }
            return nil
        }
    }

    // MARK: - timeout

    /// Parses as a bare integer (seconds) or a Go-style duration string
    /// (`s`/`m`/`h`/`ms`/`us`/`ns` suffix).
    static let duration = ConfigValidator { value, _ in
        if let intValue = value as? Int { return intValue >= 0 ? nil : "Duration must not be negative." }
        guard let string = value as? String, !string.isEmpty else { return nil }
        if Int(string) != nil { return nil }
        let pattern = "^[0-9]+(ns|us|\u{00B5}s|ms|s|m|h)$"
        if string.range(of: pattern, options: .regularExpression) == nil {
            return "\"\(string)\" isn't a valid duration (e.g. \"60s\", \"30m\", \"1h\")."
        }
        return nil
    }

    // MARK: - Enum membership

    /// Case-insensitive membership check, matching how Hugo itself compares
    /// these strings. Used by every `.choice` entry.
    static func memberOf(_ options: [String]) -> ConfigValidator {
        ConfigValidator { value, _ in
            guard let string = value as? String else { return nil }
            if string.isEmpty { return nil } // absent/blank reads as "use default"
            if !options.contains(where: { $0.caseInsensitiveCompare(string) == .orderedSame }) {
                return "\"\(string)\" is not one of: \(options.joined(separator: ", "))."
            }
            return nil
        }
    }

    // MARK: - disableKinds

    /// Each element must be a known page kind (§4.3).
    static let kindsList = ConfigValidator { value, _ in
        guard let kinds = value as? [String] else { return nil }
        let unknown = kinds.filter { !ConfigSchema.pageKinds.contains($0.lowercased()) }
        guard !unknown.isEmpty else { return nil }
        return "Unknown page kind(s): \(unknown.joined(separator: ", "))."
    }

    // MARK: - outputs.<kind>

    /// Each format name is a built-in (§4.4) or a key of the user's own
    /// `outputFormats` section.
    static let outputFormatsKnown = ConfigValidator { value, context in
        guard let formats = value as? [String] else { return nil }
        let custom = Set((context.store.subtree("outputFormats") ?? [:]).keys.map { $0.lowercased() })
        let builtIn = Set(ConfigSchema.outputFormatNames.map { $0.lowercased() })
        let known = builtIn.union(custom)
        let unknown = formats.filter { !known.contains($0.lowercased()) }
        guard !unknown.isEmpty else { return nil }
        return "Unknown output format(s): \(unknown.joined(separator: ", "))."
    }

    // MARK: - taxonomies keys / permalinks keys

    /// Reuses `PermalinkResolver.validateSectionName` rather than duplicating
    /// its rules (no slashes, no spaces, non-empty).
    static let sectionName = ConfigValidator { value, _ in
        guard let string = value as? String else { return nil }
        return PermalinkResolver.validateSectionName(string)
    }

    // MARK: - taxonomies

    /// Singular ≠ plural, no two singulars sharing a plural, lowercase recommended.
    static let taxonomyPair = ConfigValidator { value, _ in
        guard let map = value as? [String: String] else { return nil }
        var issues: [String] = []
        var singularByPlural: [String: String] = [:]
        for (singular, plural) in map.sorted(by: { $0.key < $1.key }) {
            if singular.caseInsensitiveCompare(plural) == .orderedSame {
                issues.append("\"\(singular)\": singular and plural must differ.")
            }
            if singular != singular.lowercased() || plural != plural.lowercased() {
                issues.append("\"\(singular)\"/\"\(plural)\": lowercase is recommended.")
            }
            let pluralKey = plural.lowercased()
            if let existing = singularByPlural[pluralKey], existing != singular {
                issues.append("Plural \"\(plural)\" is used by both \"\(existing)\" and \"\(singular)\".")
            }
            singularByPlural[pluralKey] = singular
        }
        return issues.isEmpty ? nil : issues.joined(separator: " ")
    }

    // MARK: - sitemap.changeFreq

    static let changeFreq = ConfigValidator { value, _ in
        guard let string = value as? String, !string.isEmpty else { return nil }
        if !ConfigSchema.sitemapChangeFreqs.contains(string.lowercased()) {
            return "\"\(string)\" is not a valid sitemap change frequency."
        }
        return nil
    }

    // MARK: - sitemap.priority

    /// -1 (the "omit" sentinel) or 0.0...1.0.
    static let priorityRange = ConfigValidator { value, _ in
        let priority: Double?
        if let d = value as? Double {
            priority = d
        } else if let i = value as? Int {
            priority = Double(i)
        } else if let s = value as? String {
            priority = Double(s)
        } else {
            priority = nil
        }
        guard let priority else { return "Expected a number." }
        if priority == -1 { return nil }
        if priority < 0 || priority > 1 {
            return "Priority must be -1 (omit from sitemap) or between 0.0 and 1.0."
        }
        return nil
    }

    // MARK: - imaging.bgColor

    static let hexColor = ConfigValidator { value, _ in
        guard let string = value as? String, !string.isEmpty else { return nil }
        let pattern = "^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$"
        if string.range(of: pattern, options: .regularExpression) == nil {
            return "\"\(string)\" is not a valid hex color (#rgb or #rrggbb)."
        }
        return nil
    }
}
