import XCTest
@testable import Victor

/// Tests for EditorActions' Equatable contract (keystroke-lag fix, part 2).
///
/// EditorActions is published via `.focusedValue` from the editor panels' `body`.
/// Those bodies can re-evaluate frequently (cursor moves, dirty-state reads), and
/// each evaluation constructs a fresh EditorActions. Without Equatable, SwiftUI
/// must treat every publish as a change, invalidating every `@FocusedValue`
/// holder - including VictorApp's body and with it the entire `.commands` menu
/// tree - on every keystroke. Equality keyed on the *editor's identity* (the file
/// node id) lets SwiftUI skip all of that until the user actually switches files.
///
/// Closures are deliberately excluded from equality: they capture `@State`/
/// `@Observable` references and read live values at call time, so two instances
/// for the same editor are behaviorally interchangeable even though their
/// closures are never `==`-comparable.
@MainActor
final class EditorActionsTests: XCTestCase {

    private func makeActions(
        id: UUID,
        formatting: ((MarkdownFormat) -> Void)? = nil,
        hasUnsavedChanges: @escaping () -> Bool = { false }
    ) -> EditorActions {
        EditorActions(
            editorID: id,
            formatting: formatting,
            showShortcodePicker: nil,
            save: { true },
            revert: {},
            hasUnsavedChanges: hasUnsavedChanges
        )
    }

    /// Same editor identity must compare equal even when every closure differs -
    /// this is what stops per-keystroke focused-value republish from cascading.
    func testSameEditorIDComparesEqualRegardlessOfClosures() {
        let id = UUID()
        let a = makeActions(id: id, formatting: { _ in }, hasUnsavedChanges: { true })
        let b = makeActions(id: id, formatting: nil, hasUnsavedChanges: { false })

        XCTAssertEqual(a, b, "EditorActions for the same editor must be equal; closures are excluded from identity")
    }

    /// Different editors (file switch) must compare unequal so the menu bar
    /// picks up the new file's actions.
    func testDifferentEditorIDsCompareUnequal() {
        let a = makeActions(id: UUID())
        let b = makeActions(id: UUID())

        XCTAssertNotEqual(a, b, "A file switch changes the editor identity and must republish the focused value")
    }
}
