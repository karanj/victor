import XCTest
@testable import Victor

/// A schema entry earns its row by giving the user something to do. An entry
/// that is *both* deprecated and has no working control renders as
/// "Deprecated" + "Coming in a later phase — edit in Raw for now" on the
/// Advanced tab: a row that tells you not to use the key and won't let you
/// edit it either. Keys like that belong in the file, not in the schema —
/// `ConfigValueStore` round-trips them regardless, and the Advanced tab's
/// Unknown Keys section gives them a real recursive editor.
final class ConfigSchemaPlaceholderTests: XCTestCase {

    /// Types `ConfigFieldView` renders as `ConfigComingLaterRow` rather than
    /// an editable control.
    private func hasNoWorkingControl(_ type: ConfigValueType) -> Bool {
        switch type {
        case .dictionary, .stringMap, .rawOnly: return true
        default: return false
        }
    }

    func testNoEntryIsBothDeprecatedAndUneditable() {
        let dead = ConfigSchema.all.filter {
            $0.deprecation != nil && hasNoWorkingControl($0.type)
        }
        XCTAssertTrue(
            dead.isEmpty,
            "Deprecated entries with no editable control: \(dead.map(\.key))"
        )
    }

    /// The two entries dropped for exactly that reason. Both are still
    /// preserved and editable if present in a file — as unknown keys.
    func testDroppedLegacyDictionaryEntriesAreGone() {
        XCTAssertNil(ConfigSchema.spec(for: "author"))
        XCTAssertNil(ConfigSchema.spec(for: "social"))
    }

    /// …and dropping them must leave them classified as unknown, so the
    /// Advanced tab still shows a real editor for a file that has them.
    func testDroppedKeysClassifyAsUnknown() {
        let schemaKeys = ConfigSchema.all.map(\.key)
        for key in ["author", "social"] {
            XCTAssertEqual(
                ConfigAdvancedKeyClassifier.classify(
                    rootKey: key,
                    schemaKeys: schemaKeys,
                    rawOnlySectionKeys: ConfigSchema.rawOnlySectionKeys
                ),
                .unknown,
                "\(key) should fall through to the Unknown Keys editor"
            )
        }
    }
}
