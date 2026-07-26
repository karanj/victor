import XCTest
@testable import Victor

/// Tests for `ConfigOutputsMatrix` — the pure read/toggle/write-back logic
/// behind the Integrations tab's bespoke output-formats matrix
/// (CONFIG-SCHEMA-SPEC §3.6/§4.4, Phase 5 task brief item 3).
final class ConfigOutputsMatrixTests: XCTestCase {

    // MARK: - columns

    func testColumnsAreBuiltInsThenCustomFormats() {
        let columns = ConfigOutputsMatrix.columns(customFormatKeys: ["ld-json", "epub"])
        XCTAssertEqual(columns.prefix(ConfigSchema.outputFormatNames.count), ArraySlice(ConfigSchema.outputFormatNames))
        XCTAssertEqual(Array(columns.suffix(2)), ["ld-json", "epub"])
    }

    func testColumnsDeduplicateCaseInsensitively() {
        // "HTML" collides with the built-in "html" — built-in wins the slot.
        let columns = ConfigOutputsMatrix.columns(customFormatKeys: ["HTML", "custom"])
        XCTAssertEqual(columns.filter { $0.caseInsensitiveCompare("html") == .orderedSame }.count, 1)
        XCTAssertTrue(columns.contains("html"))
        XCTAssertFalse(columns.contains("HTML"))
        XCTAssertTrue(columns.contains("custom"))
    }

    func testColumnsWithNoCustomFormatsIsJustBuiltIns() {
        XCTAssertEqual(ConfigOutputsMatrix.columns(customFormatKeys: []), ConfigSchema.outputFormatNames)
    }

    // MARK: - normalizedOutputs

    func testNormalizedOutputsHandlesStringArrayAnyArrayAndSingleString() {
        let raw: [String: Any] = [
            "home": ["html", "rss"] as [String],
            "page": ["html"] as [Any],
            "term": "html"
        ]
        let normalized = ConfigOutputsMatrix.normalizedOutputs(from: raw)
        XCTAssertEqual(normalized["home"], ["html", "rss"])
        XCTAssertEqual(normalized["page"], ["html"])
        XCTAssertEqual(normalized["term"], ["html"])
    }

    func testNormalizedOutputsDropsUnrecognizedShapes() {
        let raw: [String: Any] = ["home": 42]
        XCTAssertNil(ConfigOutputsMatrix.normalizedOutputs(from: raw)["home"])
    }

    // MARK: - checkedFormats

    func testCheckedFormatsPresentKindReturnsStoredArray() {
        let (formats, isPresent) = ConfigOutputsMatrix.checkedFormats(for: "home", outputs: ["home": ["html", "amp"]])
        XCTAssertEqual(formats, ["html", "amp"])
        XCTAssertTrue(isPresent)
    }

    func testCheckedFormatsAbsentKindFallsBackToDefaultDimmed() {
        let (formats, isPresent) = ConfigOutputsMatrix.checkedFormats(for: "page", outputs: [:])
        XCTAssertEqual(formats, ["html"])
        XCTAssertFalse(isPresent)
    }

    func testDefaultOutputsMatchSpecSection44() {
        XCTAssertEqual(ConfigOutputsMatrix.defaultOutputs["page"], ["html"])
        for kind in ["home", "section", "taxonomy", "term"] {
            XCTAssertEqual(ConfigOutputsMatrix.defaultOutputs[kind], ["html", "rss"])
        }
    }

    // MARK: - toggling

    func testTogglingOnAppendsFormat() {
        let result = ConfigOutputsMatrix.toggling(format: "amp", newState: true, currentlyChecked: ["html"])
        XCTAssertEqual(result, ["html", "amp"])
    }

    func testTogglingOnIsIdempotentCaseInsensitively() {
        let result = ConfigOutputsMatrix.toggling(format: "html", newState: true, currentlyChecked: ["HTML"])
        XCTAssertEqual(result, ["HTML"], "toggling on an already-checked format (any casing) must not duplicate it")
    }

    func testTogglingOffRemovesFormatCaseInsensitively() {
        let result = ConfigOutputsMatrix.toggling(format: "html", newState: false, currentlyChecked: ["HTML", "rss"])
        XCTAssertEqual(result, ["rss"])
    }

    func testTogglingOffLastFormatReturnsNil() {
        let result = ConfigOutputsMatrix.toggling(format: "html", newState: false, currentlyChecked: ["html"])
        XCTAssertNil(result, "an empty result must signal 'remove the kind key', never an empty array")
    }

    // MARK: - applyToggle (full outputs dict, including untouched kinds)

    func testApplyToggleMaterializesAbsentKindFromDefaults() {
        let updated = ConfigOutputsMatrix.applyToggle(kind: "page", format: "amp", isOn: true, in: [:])
        XCTAssertEqual(Set(updated["page"] ?? []), Set(["html", "amp"]), "toggling an absent/default row writes the full default set plus the new format")
    }

    func testApplyToggleRemovesKindKeyWhenLastFormatUnchecked() {
        let updated = ConfigOutputsMatrix.applyToggle(kind: "page", format: "html", isOn: false, in: ["page": ["html"]])
        XCTAssertNil(updated["page"])
    }

    func testApplyTogglePreservesOtherKindsUntouched() {
        let updated = ConfigOutputsMatrix.applyToggle(
            kind: "home", format: "amp", isOn: true,
            in: ["home": ["html"], "page": ["html"], "404": ["html"]]
        )
        XCTAssertEqual(updated["page"], ["html"])
        XCTAssertEqual(updated["404"], ["html"], "kinds outside the 5 matrix rows must pass through untouched")
    }

    // MARK: - storageValue (empty outputs -> remove the whole key)

    func testStorageValueNilForEmptyDict() {
        XCTAssertNil(ConfigOutputsMatrix.storageValue(for: [:]))
    }

    func testStorageValueNonNilForNonEmptyDict() {
        XCTAssertNotNil(ConfigOutputsMatrix.storageValue(for: ["home": ["html"]]))
    }

    func testUncheckingEveryFormatEndToEndRemovesOutputsKey() {
        // "empty array after unchecking everything -> remove the kind key;
        // empty outputs -> remove outputs" -- exercised end-to-end.
        var outputs: [String: [String]] = ["page": ["html"]]
        outputs = ConfigOutputsMatrix.applyToggle(kind: "page", format: "html", isOn: false, in: outputs)
        XCTAssertTrue(outputs.isEmpty)
        XCTAssertNil(ConfigOutputsMatrix.storageValue(for: outputs))
    }
}
