import XCTest
@testable import Victor

/// Tests for `ConfigLocaleResolver` — the pure logic behind the Essentials
/// tab's single bespoke "Locale" row (CONFIG-SCHEMA-SPEC §7.1, Phase 5 task
/// brief item 4).
final class ConfigLocaleResolutionTests: XCTestCase {

    func testNeitherPresentWritesLocaleAndShowsEmpty() {
        let resolution = ConfigLocaleResolver.resolve(localeValue: nil, languageCodeValue: nil)
        XCTAssertEqual(resolution.value, "")
        XCTAssertEqual(resolution.writeKey, "locale")
        XCTAssertFalse(resolution.displayedFromDeprecatedKey)
        XCTAssertNil(resolution.bothPresentLintMessage)
    }

    func testOnlyLocalePresentDisplaysAndWritesLocale() {
        let resolution = ConfigLocaleResolver.resolve(localeValue: "en-US", languageCodeValue: nil)
        XCTAssertEqual(resolution.value, "en-US")
        XCTAssertEqual(resolution.writeKey, "locale")
        XCTAssertFalse(resolution.displayedFromDeprecatedKey)
        XCTAssertNil(resolution.bothPresentLintMessage)
    }

    func testOnlyLanguageCodePresentDisplaysAndWritesLanguageCodeWithBadge() {
        let resolution = ConfigLocaleResolver.resolve(localeValue: nil, languageCodeValue: "en-us")
        XCTAssertEqual(resolution.value, "en-us")
        XCTAssertEqual(resolution.writeKey, "languageCode", "edits must write back to whichever key the file has")
        XCTAssertTrue(resolution.displayedFromDeprecatedKey)
        XCTAssertNil(resolution.bothPresentLintMessage)
    }

    func testBothPresentLocaleWinsAndLintsLanguageCode() {
        let resolution = ConfigLocaleResolver.resolve(localeValue: "en-GB", languageCodeValue: "en-us")
        XCTAssertEqual(resolution.value, "en-GB", "locale wins when both are present, matching Hugo's own read-side migration")
        XCTAssertEqual(resolution.writeKey, "locale")
        XCTAssertFalse(resolution.displayedFromDeprecatedKey)
        XCTAssertNotNil(resolution.bothPresentLintMessage)
    }

    func testBothPresentWithEmptyLocaleStillTreatsLocaleAsPresent() {
        // Presence is structural (key exists), not "non-empty" -- an
        // explicitly-set empty locale still wins over languageCode.
        let resolution = ConfigLocaleResolver.resolve(localeValue: "", languageCodeValue: "en-us")
        XCTAssertEqual(resolution.value, "")
        XCTAssertEqual(resolution.writeKey, "locale")
        XCTAssertNotNil(resolution.bothPresentLintMessage)
    }
}
