import XCTest
import SwiftUI
@testable import Victor

/// Tests for reusable state views: LoadingStateView, ErrorStateView, EmptyStateView
@MainActor
final class StateViewTests: XCTestCase {

    // MARK: - LoadingStateView Tests

    func testLoadingStateViewRendersWithMessage() {
        let view = LoadingStateView(message: "Loading assets...")
        // Verify the view can be constructed and its body accessed
        let _ = view.body
    }

    func testLoadingStateViewAcceptsArbitraryMessage() {
        let messages = ["Searching...", "Loading configuration...", "Loading template..."]
        for message in messages {
            let view = LoadingStateView(message: message)
            let _ = view.body
        }
    }

    // MARK: - ErrorStateView Tests

    func testErrorStateViewRendersWithTitleAndMessage() {
        let view = ErrorStateView(
            title: "Failed to load",
            message: "The file could not be read"
        )
        let _ = view.body
    }

    func testErrorStateViewRendersWithRetryAction() {
        var retryCalled = false
        let view = ErrorStateView(
            title: "Error",
            message: "Something went wrong",
            retryAction: { retryCalled = true }
        )
        let _ = view.body
        // Verify the closure is stored (not called during render)
        XCTAssertFalse(retryCalled)
    }

    func testErrorStateViewRendersWithOpenURL() {
        let url = URL(fileURLWithPath: "/tmp/test.txt")
        let view = ErrorStateView(
            title: "Error",
            message: "Could not parse file",
            openURL: url
        )
        let _ = view.body
    }

    func testErrorStateViewRendersWithAllOptions() {
        let url = URL(fileURLWithPath: "/tmp/test.txt")
        let view = ErrorStateView(
            title: "Failed to load data file",
            message: "Invalid YAML format",
            retryAction: {},
            openURL: url
        )
        let _ = view.body
    }

    func testErrorStateViewRendersWithNoOptionalParams() {
        let view = ErrorStateView(
            title: "Error",
            message: "Details here"
        )
        // No retryAction, no openURL — should still render
        let _ = view.body
    }

    // MARK: - EmptyStateView Tests (sanity checks)

    func testEmptyStateViewRendersWithoutAction() {
        let view = EmptyStateView(
            icon: "doc.text",
            title: "No File Selected",
            message: "Select a file to view its metadata"
        )
        let _ = view.body
    }

    func testEmptyStateViewRendersWithAction() {
        let view = EmptyStateView(
            icon: "magnifyingglass",
            title: "No Results",
            message: "Try a different search",
            actionLabel: "Clear Filters"
        ) {
            // action
        }
        let _ = view.body
    }

    func testEmptyStateViewRendersWithActionAndIcon() {
        let view = EmptyStateView(
            icon: "folder",
            title: "No Assets",
            message: "Add files to this directory",
            actionLabel: "Open in Finder",
            actionIcon: "folder"
        ) {
            // action
        }
        let _ = view.body
    }
}
