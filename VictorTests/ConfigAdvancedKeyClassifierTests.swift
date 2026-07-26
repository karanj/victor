import XCTest
@testable import Victor

/// Tests for `ConfigAdvancedKeyClassifier.classify` — the pure root-key
/// classification function backing the Advanced tab's Site Params / All
/// Settings / Unknown Keys / Raw-Only split (CONFIG-SCHEMA-SPEC §3.7,
/// Config Editor v2 Phase 2).
final class ConfigAdvancedKeyClassifierTests: XCTestCase {

    private let schemaKeys = ConfigSchema.all.map(\.key)
    private let rawOnlyKeys = ConfigSchema.rawOnlySectionKeys

    private func classify(_ rootKey: String) -> ConfigRootKeyClassification {
        ConfigAdvancedKeyClassifier.classify(
            rootKey: rootKey, schemaKeys: schemaKeys, rawOnlySectionKeys: rawOnlyKeys
        )
    }

    // MARK: - Known: exact schema key match

    func testExactSchemaKeyIsKnown() {
        XCTAssertEqual(classify("baseURL"), .known)
        XCTAssertEqual(classify("summaryLength"), .known)
    }

    // MARK: - Known: schema key prefix means root is known

    func testDottedSchemaKeyPrefixMakesRootKnown() {
        // "markup.goldmark.renderer.unsafe" is a schema entry; "markup"
        // itself has no exact entry but must still classify as known.
        XCTAssertTrue(schemaKeys.contains("markup.goldmark.renderer.unsafe"))
        XCTAssertFalse(schemaKeys.contains("markup"))
        XCTAssertEqual(classify("markup"), .known)
    }

    func testPaginationRootIsKnownViaPrefix() {
        XCTAssertEqual(classify("pagination"), .known)
    }

    // MARK: - rawOnly: exact case match

    func testRawOnlySectionKeyIsRawOnly() {
        XCTAssertEqual(classify("security"), .rawOnly)
        XCTAssertEqual(classify("caches"), .rawOnly)
    }

    // MARK: - rawOnly: case-insensitive match (the documented casing note)

    func testRawOnlySectionMatchesCaseInsensitively() {
        // Schema spells these lowercase; real Hugo files write camelCase.
        XCTAssertEqual(classify("mediaTypes"), .rawOnly, "schema has 'mediatypes'")
        XCTAssertEqual(classify("outputFormats"), .rawOnly, "schema has 'outputformats'")
        XCTAssertEqual(classify("contentTypes"), .rawOnly, "schema has 'contenttypes'")
        XCTAssertEqual(classify("httpCache"), .rawOnly, "schema has 'httpcache'")
    }

    func testRawOnlyExactLowercaseAlsoMatches() {
        XCTAssertEqual(classify("mediatypes"), .rawOnly)
        XCTAssertEqual(classify("outputformats"), .rawOnly)
    }

    // MARK: - bespoke: dedicated non-generic editors elsewhere

    func testBespokeRootKeysAreBespokeNotUnknown() {
        XCTAssertEqual(classify("params"), .bespoke)
        XCTAssertEqual(classify("taxonomies"), .bespoke)
        XCTAssertEqual(classify("permalinks"), .bespoke)
        XCTAssertEqual(classify("menus"), .bespoke)
        XCTAssertEqual(classify("menu"), .bespoke)
    }

    // MARK: - unknown: matches nothing

    func testArbitraryRootKeyIsUnknown() {
        XCTAssertEqual(classify("myThemesCustomRootSetting"), .unknown)
        XCTAssertEqual(classify("someTypoedKey"), .unknown)
    }

    // MARK: - Precedence: bespoke wins even if it also happens to be a schema prefix

    func testBespokeTakesPrecedenceOverRawOnlyAndKnown() {
        // "params" is bespoke and is not a rawOnly section nor a schema
        // prefix today, but the classifier must check bespoke first
        // regardless — verify via the explicit parameter overload.
        let result = ConfigAdvancedKeyClassifier.classify(
            rootKey: "params",
            schemaKeys: ["params.somefield"], // pretend a schema entry existed under it
            rawOnlySectionKeys: ["params"],    // pretend it were also a rawOnly section
            bespokeRootKeys: ["params"]
        )
        XCTAssertEqual(result, .bespoke)
    }

    // MARK: - Real store integration smoke test

    func testUnknownKeysAgainstRealStore() {
        let store = ConfigValueStore(root: [
            "baseURL": "https://example.com/",
            "markup": ["goldmark": ["renderer": ["unsafe": true]]],
            "params": ["author": "Jane"],
            "security": ["exec": ["allow": ["^dart-sass-embedded$"]]],
            "mediaTypes": ["text/plain": ["suffixes": ["txt"]]],
            "myCustomRootKey": ["foo": "bar"]
        ])
        let classifications = Dictionary(uniqueKeysWithValues: store.orderedRootKeys.map {
            ($0, classify($0))
        })
        XCTAssertEqual(classifications["baseURL"], .known)
        XCTAssertEqual(classifications["markup"], .known)
        XCTAssertEqual(classifications["params"], .bespoke)
        XCTAssertEqual(classifications["security"], .rawOnly)
        XCTAssertEqual(classifications["mediaTypes"], .rawOnly)
        XCTAssertEqual(classifications["myCustomRootKey"], .unknown)
    }
}
