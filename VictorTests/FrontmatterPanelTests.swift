import XCTest
@testable import Victor

/// Presentation logic behind `FrontmatterBottomPanel`: one picker covers the form
/// categories and Raw, so switching panes decides when raw text is (re)built or parsed.
final class FrontmatterPanelTests: XCTestCase {

    func testFormatDisplayName() {
        XCTAssertEqual(FrontmatterFormat.yaml.displayName, "YAML")
        XCTAssertEqual(FrontmatterFormat.toml.displayName, "TOML")
        XCTAssertEqual(FrontmatterFormat.json.displayName, "JSON")
    }

    func testEnteringRawSerializes() {
        XCTAssertEqual(FrontmatterPane.form(.seo).sync(to: .raw), .serialize)
    }

    func testLeavingRawParses() {
        XCTAssertEqual(FrontmatterPane.raw.sync(to: .form(.essential)), .parse)
    }

    func testSwitchingFormCategoriesNeedsNoSync() {
        XCTAssertEqual(FrontmatterPane.form(.essential).sync(to: .form(.menus)), .none)
        XCTAssertEqual(FrontmatterPane.raw.sync(to: .raw), .none)
    }

    func testPickerOffersEveryCategoryThenRaw() {
        XCTAssertEqual(FrontmatterPane.allCases, FrontmatterTab.allCases.map { .form($0) } + [.raw])
    }
}
