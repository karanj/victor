import XCTest
@testable import Victor

/// Tests for `ConfigLintCatalog.scan` — the removed-key lint table
/// (CONFIG-SCHEMA-SPEC §2.5 mechanism 2, Phase 5 task brief item 5).
final class ConfigLintCatalogTests: XCTestCase {

    // MARK: - Each catalog entry

    func testPaginateWarnsWithPureRenameButton() {
        let store = ConfigValueStore(root: ["paginate": 20])
        let warnings = ConfigLintCatalog.scan(store: store)
        guard let warning = warnings.first(where: { $0.key == "paginate" }) else {
            return XCTFail("expected a warning for root paginate")
        }
        XCTAssertEqual(warning.replacementKey, "pagination.pagerSize")
    }

    func testPaginatePathWarnsWithPureRenameButton() {
        let store = ConfigValueStore(root: ["paginatePath": "p"])
        let warnings = ConfigLintCatalog.scan(store: store)
        guard let warning = warnings.first(where: { $0.key == "paginatePath" }) else {
            return XCTFail("expected a warning for root paginatePath")
        }
        XCTAssertEqual(warning.replacementKey, "pagination.path")
    }

    func testRootGoogleAnalyticsWarnsAsLegacyLocationWithNoRenameButton() {
        let store = ConfigValueStore(root: ["googleAnalytics": "G-XXXX"])
        let warnings = ConfigLintCatalog.scan(store: store)
        guard let warning = warnings.first(where: { $0.key == "googleAnalytics" }) else {
            return XCTFail("expected a warning for root googleAnalytics")
        }
        XCTAssertNil(warning.replacementKey, "fallback still works -- no auto-fix button")
        XCTAssertTrue(warning.message.localizedCaseInsensitiveContains("legacy location"))
    }

    func testRootDisqusShortnameWarnsAsLegacyLocationWithNoRenameButton() {
        let store = ConfigValueStore(root: ["disqusShortname": "myblog"])
        let warnings = ConfigLintCatalog.scan(store: store)
        guard let warning = warnings.first(where: { $0.key == "disqusShortname" }) else {
            return XCTFail("expected a warning for root disqusShortname")
        }
        XCTAssertNil(warning.replacementKey)
    }

    // MARK: - Permalink token scan

    func testPermalinkFilenameTokenWarns() {
        let store = ConfigValueStore(root: ["permalinks": ["posts": "/:year/:filename/"]])
        let warnings = ConfigLintCatalog.scan(store: store)
        XCTAssertTrue(warnings.contains { $0.key == "permalinks.posts" && $0.message.contains(":filename") })
    }

    func testPermalinkSlugorfilenameTokenWarns() {
        let store = ConfigValueStore(root: ["permalinks": ["posts": "/:slugorfilename/"]])
        let warnings = ConfigLintCatalog.scan(store: store)
        XCTAssertTrue(warnings.contains { $0.key == "permalinks.posts" && $0.message.contains(":slugorfilename") })
    }

    func testPermalinkTokenWarningsHaveNoRenameButton() {
        let store = ConfigValueStore(root: ["permalinks": ["posts": "/:filename/"]])
        let warning = ConfigLintCatalog.scan(store: store).first { $0.key == "permalinks.posts" }
        XCTAssertNil(warning?.replacementKey)
    }

    func testPermalinkTokenScanIgnoresNonDeprecatedPatterns() {
        let store = ConfigValueStore(root: ["permalinks": ["posts": "/:year/:month/:contentbasename/"]])
        let warnings = ConfigLintCatalog.scan(store: store)
        XCTAssertTrue(warnings.isEmpty)
    }

    func testPermalinkTokenScanHandlesNestedPageShape() {
        // Hugo also accepts the nested `permalinks.page.<section>` shape.
        let store = ConfigValueStore(root: ["permalinks": ["page": ["posts": "/:filename/"]]])
        let warnings = ConfigLintCatalog.scan(store: store)
        XCTAssertTrue(warnings.contains { $0.key == "permalinks.page.posts" })
    }

    // MARK: - Clean config: no warnings

    func testCleanConfigProducesNoWarnings() {
        let store = ConfigValueStore(root: [
            "baseURL": "https://example.com/",
            "title": "My Site",
            "pagination": ["pagerSize": 10],
            "services": ["googleAnalytics": ["ID": "G-XXXX"]],
            "permalinks": ["posts": "/:year/:month/:contentbasename/"]
        ])
        XCTAssertTrue(ConfigLintCatalog.scan(store: store).isEmpty)
    }

    func testEmptyConfigProducesNoWarnings() {
        XCTAssertTrue(ConfigLintCatalog.scan(store: ConfigValueStore(root: [:])).isEmpty)
    }

    // MARK: - Multiple findings accumulate

    func testMultipleLegacyKeysAllReported() {
        let store = ConfigValueStore(root: [
            "paginate": 10,
            "paginatePath": "page",
            "googleAnalytics": "G-XXXX",
            "disqusShortname": "myblog"
        ])
        let warnings = ConfigLintCatalog.scan(store: store)
        XCTAssertEqual(Set(warnings.map(\.key)), Set(["paginate", "paginatePath", "googleAnalytics", "disqusShortname"]))
    }
}
