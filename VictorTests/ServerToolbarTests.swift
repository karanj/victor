import XCTest
@testable import Victor

/// Pure presentation logic behind the main window toolbar's server items and the
/// secondary bar's visibility (the views themselves are thin over these).
final class ServerToolbarTests: XCTestCase {

    // MARK: - Activity view text

    func testActivityTitleForEachStatus() {
        // Short: it sits beside the Run button in the server group, which gives context.
        XCTAssertEqual(ServerActivity.title(for: .stopped, url: nil), "Stopped")
        XCTAssertEqual(ServerActivity.title(for: .starting, url: nil), "Starting…")
        XCTAssertEqual(ServerActivity.title(for: .error(message: "port in use"), url: nil), "Error")
    }

    func testRunningTitleShowsHostAndPortWhenURLKnown() {
        let url = URL(string: "http://localhost:1313/")!
        XCTAssertEqual(ServerActivity.title(for: .running(port: 1313), url: url), "localhost:1313")
    }

    func testRunningTitleFallsBackToPortBeforeURLArrives() {
        XCTAssertEqual(ServerActivity.title(for: .running(port: 1414), url: nil), "Port 1414")
    }

    func testTooltipSpellsOutTheServerState() {
        XCTAssertEqual(ServerActivity.help(for: .stopped, url: nil), "Hugo server stopped")
        XCTAssertEqual(ServerActivity.help(for: .running(port: 1313), url: URL(string: "http://localhost:1313/")), "Hugo server running at http://localhost:1313/")
        XCTAssertEqual(ServerActivity.help(for: .error(message: "port in use"), url: nil), "Hugo server error: port in use")
    }

    // MARK: - Run/Stop button

    func testRunButtonLabelFollowsStatus() {
        XCTAssertEqual(ServerActivity.runButton(for: .stopped).title, "Run Hugo Server")
        XCTAssertEqual(ServerActivity.runButton(for: .stopped).systemImage, "play.fill")
        XCTAssertEqual(ServerActivity.runButton(for: .running(port: 1313)).title, "Stop Hugo Server")
        XCTAssertEqual(ServerActivity.runButton(for: .running(port: 1313)).systemImage, "stop.fill")
        // An errored server isn't running: offer to run it again.
        XCTAssertEqual(ServerActivity.runButton(for: .error(message: "x")).systemImage, "play.fill")
    }

    func testRunButtonDisabledWhileStarting() {
        XCTAssertFalse(ServerActivity.runButton(for: .starting).isEnabled)
        XCTAssertTrue(ServerActivity.runButton(for: .stopped).isEnabled)
        XCTAssertTrue(ServerActivity.runButton(for: .running(port: 1313)).isEnabled)
    }

    // MARK: - Secondary bar visibility

    /// The layout picker moved to the toolbar; what's left (preview source picker,
    /// build issues pill) only has something to show outside Editor mode or with issues.
    func testSecondaryBarHiddenInEditorModeWithoutIssues() {
        XCTAssertFalse(TabBarView.isNeeded(layoutMode: .editor, hasBuildIssues: false))
    }

    func testSecondaryBarShownForBuildIssuesOrPreviewModes() {
        XCTAssertTrue(TabBarView.isNeeded(layoutMode: .editor, hasBuildIssues: true))
        XCTAssertTrue(TabBarView.isNeeded(layoutMode: .preview, hasBuildIssues: false))
        XCTAssertTrue(TabBarView.isNeeded(layoutMode: .split, hasBuildIssues: false))
    }
}
