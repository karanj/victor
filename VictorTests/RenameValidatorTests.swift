import XCTest
@testable import Victor

/// Tests for RenameValidator, the pure validation function backing RenameSheet's
/// Confirm-button disabling / inline error message (victor-rnm). No I/O, no
/// SiteViewModel/FileNode fixture needed - the function only takes strings.
final class RenameValidatorTests: XCTestCase {

    func testEmptyNameIsRejected() {
        XCTAssertEqual(
            RenameValidator.validate(newName: "", currentName: "post.md", existingSiblingNames: []),
            .empty
        )
    }

    func testWhitespaceOnlyNameIsRejected() {
        XCTAssertEqual(
            RenameValidator.validate(newName: "   ", currentName: "post.md", existingSiblingNames: []),
            .empty
        )
    }

    func testNameContainingSlashIsRejected() {
        XCTAssertEqual(
            RenameValidator.validate(newName: "sub/post.md", currentName: "post.md", existingSiblingNames: []),
            .invalidCharacters
        )
    }

    func testNameContainingColonIsRejected() {
        XCTAssertEqual(
            RenameValidator.validate(newName: "post:draft.md", currentName: "post.md", existingSiblingNames: []),
            .invalidCharacters
        )
    }

    func testCollidingNameIsRejected() {
        XCTAssertEqual(
            RenameValidator.validate(
                newName: "other.md",
                currentName: "post.md",
                existingSiblingNames: ["other.md", "third.md"]
            ),
            .collision
        )
    }

    func testCollisionCheckIsCaseInsensitive() {
        // APFS default-formats case-insensitive: "Other.md" and "other.md" collide.
        XCTAssertEqual(
            RenameValidator.validate(
                newName: "OTHER.MD",
                currentName: "post.md",
                existingSiblingNames: ["other.md"]
            ),
            .collision
        )
    }

    func testRenamingToOwnCurrentNameIsNotACollision() {
        // Case-only correction of the file's own name (e.g. "Post.MD" -> "post.md")
        // must not be flagged as colliding with itself.
        XCTAssertNil(
            RenameValidator.validate(
                newName: "POST.MD",
                currentName: "post.md",
                existingSiblingNames: ["other.md"]
            )
        )
    }

    func testValidUniqueNameIsAccepted() {
        XCTAssertNil(
            RenameValidator.validate(
                newName: "renamed.md",
                currentName: "post.md",
                existingSiblingNames: ["other.md", "third.md"]
            )
        )
    }
}
