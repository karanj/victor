import XCTest
@testable import Victor

/// Tests for `FormRawToggleHandler`.
///
/// The handlers report success so the caller can revert the mode switch. Landing in the other
/// mode after a failed conversion strands the user's edits in the mode they just left, and the
/// next toggle back overwrites them from the stale side.
final class FormRawToggleHandlerTests: XCTestCase {

    // MARK: - Form -> Raw

    func testFormToRawReturnsTrueOnSuccess() {
        var parseError: String?

        let ok = FormRawToggleHandler.handleFormToRaw(serializeToRaw: {}, parseError: &parseError)

        XCTAssertTrue(ok)
        XCTAssertNil(parseError)
    }

    func testFormToRawClearsStaleErrorOnSuccess() {
        var parseError: String? = "an earlier failure"

        _ = FormRawToggleHandler.handleFormToRaw(serializeToRaw: {}, parseError: &parseError)

        XCTAssertNil(parseError, "a successful conversion must clear the previous error")
    }

    func testFormToRawReturnsFalseAndReportsOnFailure() {
        var parseError: String?
        let failure = NSError(
            domain: "Test", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "array root"]
        )

        let ok = FormRawToggleHandler.handleFormToRaw(
            serializeToRaw: { throw failure },
            parseError: &parseError
        )

        XCTAssertFalse(ok, "caller needs this to revert the toggle")
        XCTAssertNotNil(parseError)
        XCTAssertTrue(parseError?.contains("array root") == true, "should carry the underlying reason")
    }

    // MARK: - Raw -> Form

    func testRawToFormReturnsTrueOnSuccess() {
        var parseError: String? = "an earlier failure"

        let ok = FormRawToggleHandler.handleRawToForm(parseFromRaw: {}, parseError: &parseError)

        XCTAssertTrue(ok)
        XCTAssertNil(parseError)
    }

    func testRawToFormReturnsFalseAndReportsOnFailure() {
        var parseError: String?
        let failure = NSError(
            domain: "Test", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "unclosed bracket"]
        )

        let ok = FormRawToggleHandler.handleRawToForm(
            parseFromRaw: { throw failure },
            parseError: &parseError
        )

        XCTAssertFalse(ok, "caller needs this to revert the toggle")
        XCTAssertTrue(parseError?.contains("unclosed bracket") == true)
    }
}
