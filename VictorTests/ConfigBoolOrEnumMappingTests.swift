import XCTest
@testable import Victor

/// Tests for `ConfigBoolOrEnumMapping` — the store-value ↔ picker-selection
/// mapping backing `.boolOrEnum` fields (Phase 4, `markup.highlight.lineNos`:
/// CONFIG-SCHEMA-SPEC §2.6/§3.5). Pure logic extracted out of
/// `ConfigFieldView`'s `ConfigBoolOrEnumFieldRow` specifically so it's
/// testable without a view/store in scope.
final class ConfigBoolOrEnumMappingTests: XCTestCase {

    private let options = ["inline", "table"]

    // MARK: - selection(for:options:)

    func testNilRawValueMapsToNilSelection() {
        XCTAssertNil(ConfigBoolOrEnumMapping.selection(for: nil, options: options))
    }

    func testBoolTrueMapsToOn() {
        XCTAssertEqual(ConfigBoolOrEnumMapping.selection(for: true, options: options), .on)
    }

    func testBoolFalseMapsToOff() {
        XCTAssertEqual(ConfigBoolOrEnumMapping.selection(for: false, options: options), .off)
    }

    func testKnownEnumCaseStringMapsToEnumCase() {
        XCTAssertEqual(ConfigBoolOrEnumMapping.selection(for: "inline", options: options), .enumCase("inline"))
        XCTAssertEqual(ConfigBoolOrEnumMapping.selection(for: "table", options: options), .enumCase("table"))
    }

    func testStringTrueFalseMapLeniently() {
        XCTAssertEqual(ConfigBoolOrEnumMapping.selection(for: "true", options: options), .on)
        XCTAssertEqual(ConfigBoolOrEnumMapping.selection(for: "TRUE", options: options), .on)
        XCTAssertEqual(ConfigBoolOrEnumMapping.selection(for: "false", options: options), .off)
    }

    func testIntZeroOneMapLeniently() {
        XCTAssertEqual(ConfigBoolOrEnumMapping.selection(for: 0, options: options), .off)
        XCTAssertEqual(ConfigBoolOrEnumMapping.selection(for: 1, options: options), .on)
    }

    func testUnrecognizedStringMapsToNil() {
        XCTAssertNil(ConfigBoolOrEnumMapping.selection(for: "sideways", options: options))
    }

    func testUnrecognizedIntMapsToNil() {
        XCTAssertNil(ConfigBoolOrEnumMapping.selection(for: 42, options: options))
    }

    // MARK: - storeValue(for:)

    func testStoreValueForOffIsBoolFalse() {
        let value = ConfigBoolOrEnumMapping.storeValue(for: .off)
        XCTAssertEqual(value as? Bool, false)
    }

    func testStoreValueForOnIsBoolTrue() {
        let value = ConfigBoolOrEnumMapping.storeValue(for: .on)
        XCTAssertEqual(value as? Bool, true)
    }

    func testStoreValueForEnumCaseIsString() {
        let value = ConfigBoolOrEnumMapping.storeValue(for: .enumCase("inline"))
        XCTAssertEqual(value as? String, "inline")
    }

    // MARK: - Round-trip

    func testRoundTripThroughStoreValueAndBackToSelection() {
        for selection: ConfigBoolOrEnumSelection in [.off, .on, .enumCase("inline"), .enumCase("table")] {
            let stored = ConfigBoolOrEnumMapping.storeValue(for: selection)
            XCTAssertEqual(ConfigBoolOrEnumMapping.selection(for: stored, options: options), selection)
        }
    }
}
