import XCTest
@testable import Victor

/// Tests for `ConfigSchema` and `ConfigValidators` — Phase 1b of Config Editor v2.
/// Enforces the table invariants from CONFIG-SCHEMA-SPEC.md §5 ("Phase 1 —
/// ConfigSchemaTests") plus a validator sample. These tests exist to catch
/// schema-table drift (typos, duplicate keys, mistyped defaults) at test time
/// rather than at review time — the table itself is data, not logic.
final class ConfigSchemaTests: XCTestCase {

    // MARK: - Keys unique + non-empty

    func testAllKeysAreUniqueAndNonEmpty() {
        let keys = ConfigSchema.all.map(\.key)
        for key in keys {
            XCTAssertFalse(key.isEmpty, "Schema entry has an empty key")
        }
        let uniqueKeys = Set(keys)
        XCTAssertEqual(uniqueKeys.count, keys.count, "Schema has duplicate keys: \(duplicates(in: keys))")
    }

    private func duplicates(in keys: [String]) -> [String] {
        var seen = Set<String>()
        var dupes = Set<String>()
        for key in keys {
            if !seen.insert(key).inserted { dupes.insert(key) }
        }
        return Array(dupes)
    }

    // MARK: - Every .choice non-empty

    func testEveryChoiceHasNonEmptyOptions() {
        for entry in ConfigSchema.all {
            if case .choice(let options) = entry.type {
                XCTAssertFalse(options.isEmpty, "\(entry.key) is .choice with no options")
            }
            if case .boolOrEnum(let options) = entry.type {
                XCTAssertFalse(options.isEmpty, "\(entry.key) is .boolOrEnum with no options")
            }
        }
    }

    // MARK: - Every group has at least one entry

    /// `.menus` is the one documented exception: the Menus tab is fully
    /// bespoke (CONFIG-SCHEMA-SPEC §3.4/§2.9 — menus are parsed into
    /// `HugoMenuItem` and never go through `ConfigSettingSpec`/`ConfigFieldView`),
    /// so it deliberately has zero schema entries. See Phase 1b ambiguity notes.
    func testEveryGroupExceptMenusHasAtLeastOneEntry() {
        let entriesByGroup = Dictionary(grouping: ConfigSchema.all, by: \.group)
        for group in ConfigGroup.allCases where group != .menus {
            XCTAssertFalse(
                (entriesByGroup[group] ?? []).isEmpty,
                "ConfigGroup.\(group.rawValue) has no schema entries"
            )
        }
    }

    // MARK: - Defaults type-match their declared ConfigValueType

    func testDefaultsTypeMatchDeclaredType() {
        for entry in ConfigSchema.all {
            XCTAssertTrue(
                defaultTypeMatches(entry),
                "\(entry.key): default value doesn't match declared type \(entry.type)"
            )
        }
    }

    private func defaultTypeMatches(_ entry: ConfigSettingSpec) -> Bool {
        let value: Any?
        switch entry.defaultValue {
        case .value(let v): value = v
        case .sentinel(let v, _): value = v
        case .none: return true
        }
        guard let value else { return true }
        switch entry.type {
        case .bool: return value is Bool
        case .string: return value is String
        case .int: return value is Int
        case .double: return value is Double
        case .duration: return value is String || value is Int
        case .stringArray: return value is [String]
        case .stringMap: return value is [String: String]
        case .choice: return value is String
        case .boolOrEnum: return value is Bool || value is String
        case .stringOrStringArray: return value is String || value is [String]
        case .boolOrSectionMap: return value is Bool || value is [String: Bool]
        case .dictionary: return value is [String: Any] || value is [String: String]
        case .rawOnly: return false // rawOnly entries carry no typed default
        }
    }

    // MARK: - Deprecated entries have non-empty messages

    func testDeprecatedEntriesHaveNonEmptyMessages() {
        let deprecated = ConfigSchema.all.compactMap(\.deprecation)
        XCTAssertFalse(deprecated.isEmpty, "Expected at least one deprecated schema entry")
        for deprecation in deprecated {
            XCTAssertFalse(deprecation.message.isEmpty)
            XCTAssertFalse(deprecation.since.isEmpty)
        }
    }

    // MARK: - No schema key collides with a rawOnly section prefix

    func testNoSchemaKeyCollidesWithRawOnlySectionPrefix() {
        let rawOnlyPrefixes = ConfigSchema.rawOnlySectionKeys
        for entry in ConfigSchema.all {
            guard !rawOnlyPrefixes.contains(entry.key) else { continue } // the rawOnly entry itself
            for prefix in rawOnlyPrefixes {
                XCTAssertFalse(
                    entry.key.hasPrefix(prefix + "."),
                    "\(entry.key) collides with rawOnly section \(prefix)"
                )
            }
        }
    }

    func testRawOnlySectionCountMatchesSpec() {
        // §3.7 "Raw-only sections" list: 19 entries.
        XCTAssertEqual(ConfigSchema.rawOnlySectionKeys.count, 19)
    }

    // MARK: - Spot-check known defaults (guards accidental edits)

    private func spec(_ key: String) -> ConfigSettingSpec? {
        ConfigSchema.all.first { $0.key == key }
    }

    private func defaultValue(_ key: String) -> Any? {
        guard let entry = spec(key) else { return nil }
        switch entry.defaultValue {
        case .value(let v): return v
        case .sentinel(let v, _): return v
        case .none: return nil
        }
    }

    func testSpotCheckSummaryLength() {
        XCTAssertEqual(defaultValue("summaryLength") as? Int, 70)
    }

    func testSpotCheckTitleCaseStyle() {
        XCTAssertEqual(defaultValue("titleCaseStyle") as? String, "ap")
    }

    func testSpotCheckPluralizeListTitles() {
        XCTAssertEqual(defaultValue("pluralizeListTitles") as? Bool, true)
    }

    func testSpotCheckRespectDoNotTrack() {
        XCTAssertEqual(defaultValue("privacy.googleAnalytics.respectDoNotTrack") as? Bool, true)
    }

    func testSpotCheckHighlightStyle() {
        XCTAssertEqual(defaultValue("markup.highlight.style") as? String, "monokai")
    }

    func testSpotCheckTableOfContentsStartLevel() {
        XCTAssertEqual(defaultValue("markup.tableOfContents.startLevel") as? Int, 2)
    }

    func testSpotCheckPaginationPagerSize() {
        XCTAssertEqual(defaultValue("pagination.pagerSize") as? Int, 10)
    }

    func testSpotCheckRelatedThreshold() {
        XCTAssertEqual(defaultValue("related.threshold") as? Int, 80)
    }

    func testSpotCheckImagingQuality() {
        XCTAssertEqual(defaultValue("imaging.quality") as? Int, 75)
    }

    func testSpotCheckTimeout() {
        XCTAssertEqual(defaultValue("timeout") as? String, "60s")
    }

    // MARK: - Sentinel defaults render meaning, not the raw sentinel number

    func testSitemapPrioritySentinel() {
        guard case .sentinel(let value, let meaning) = spec("sitemap.priority")!.defaultValue else {
            return XCTFail("sitemap.priority should be a sentinel default")
        }
        XCTAssertEqual(value as? Double, -1.0)
        XCTAssertEqual(meaning, "omitted from sitemap")
    }

    func testRSSLimitSentinel() {
        guard case .sentinel(let value, let meaning) = spec("services.rss.limit")!.defaultValue else {
            return XCTFail("services.rss.limit should be a sentinel default")
        }
        XCTAssertEqual(value as? Int, -1)
        XCTAssertEqual(meaning, "unlimited")
    }

    // MARK: - languageCode deprecation

    func testLanguageCodeCarriesDeprecation() {
        guard let entry = spec("languageCode") else { return XCTFail("languageCode missing from schema") }
        XCTAssertEqual(entry.deprecation?.since, "0.158.0")
        XCTAssertEqual(entry.deprecation?.replacementKey, "locale")
    }

    // MARK: - Chroma styles catalog

    func testChromaStylesCatalogIsNonEmptyAndContainsDefault() {
        XCTAssertTrue(ConfigSchema.chromaStyles.contains("monokai"))
        XCTAssertEqual(ConfigSchema.chromaStyles.count, Set(ConfigSchema.chromaStyles).count, "duplicate chroma style name")
    }

    // MARK: - Validator sample

    private func context(store: ConfigValueStore = ConfigValueStore(root: [:])) -> ValidationContext {
        ValidationContext(siteURL: nil, store: store)
    }

    func testAbsoluteURLValidator() {
        XCTAssertNil(ConfigValidators.absoluteURL.validate("https://example.com/", context()))
        XCTAssertNotNil(ConfigValidators.absoluteURL.validate("not-a-url", context()))
        XCTAssertNotNil(ConfigValidators.absoluteURL.validate("https://example.com", context()), "missing trailing slash should warn")
    }

    func testIntRangeValidator() {
        let validator = ConfigValidators.intRange(min: 1, max: 10)
        XCTAssertNil(validator.validate(5, context()))
        XCTAssertNotNil(validator.validate(0, context()))
        XCTAssertNotNil(validator.validate(11, context()))
    }

    func testDurationValidator() {
        XCTAssertNil(ConfigValidators.duration.validate("60s", context()))
        XCTAssertNil(ConfigValidators.duration.validate("5", context()))
        XCTAssertNotNil(ConfigValidators.duration.validate("not-a-duration", context()))
    }

    func testPriorityRangeValidator() {
        XCTAssertNil(ConfigValidators.priorityRange.validate(-1.0, context()), "-1 sentinel is valid (omit)")
        XCTAssertNil(ConfigValidators.priorityRange.validate(0.5, context()))
        XCTAssertNotNil(ConfigValidators.priorityRange.validate(1.5, context()))
    }

    func testTaxonomyPairValidator() {
        XCTAssertNil(ConfigValidators.taxonomyPair.validate(["tag": "tags", "category": "categories"], context()))
        XCTAssertNotNil(ConfigValidators.taxonomyPair.validate(["tag": "tag"], context()), "singular == plural should warn")
    }

    func testHexColorValidator() {
        XCTAssertNil(ConfigValidators.hexColor.validate("#ffffff", context()))
        XCTAssertNil(ConfigValidators.hexColor.validate("#fff", context()))
        XCTAssertNotNil(ConfigValidators.hexColor.validate("not-a-color", context()))
    }

    func testThemeExistsValidatorSkippedWhenModulePresent() {
        let store = ConfigValueStore(root: ["module": ["imports": [Any]()]])
        XCTAssertNil(ConfigValidators.themeExists.validate("some-theme", context(store: store)))
    }
}
