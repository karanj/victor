import AppKit
import XCTest
@testable import Victor

/// NavigationSplitView is backed by an NSSplitViewController on macOS; these
/// stand in for it with a hand-built one, since SwiftUI's isn't reachable from a test.
@MainActor
final class SidebarCollapseLockTests: XCTestCase {

    private func makeWindow() -> (NSWindow, sidebar: NSSplitViewItem, content: NSSplitViewItem, inspector: NSSplitViewItem) {
        let controller = NSSplitViewController()
        let sidebar = NSSplitViewItem(sidebarWithViewController: NSViewController.blank())
        let content = NSSplitViewItem(viewController: NSViewController.blank())
        let inspector = NSSplitViewItem(inspectorWithViewController: NSViewController.blank())
        [sidebar, content, inspector].forEach(controller.addSplitViewItem)
        let window = NSWindow(contentViewController: controller)
        return (window, sidebar, content, inspector)
    }

    func testLocksOnlyTheSidebarItem() {
        let (window, sidebar, _, inspector) = makeWindow()
        XCTAssertTrue(sidebar.canCollapse, "precondition: AppKit default for sidebars")

        XCTAssertTrue(SidebarCollapseLock.apply(in: window))

        XCTAssertFalse(sidebar.canCollapse, "drag past min width must not collapse the sidebar")
        XCTAssertFalse(sidebar.canCollapseFromWindowResize)
        XCTAssertTrue(inspector.canCollapse, "inspector keeps drag-to-close")
    }

    func testFindsSplitViewNestedBelowTheContentView() {
        let (inner, sidebar, _, _) = makeWindow()
        let host = NSViewController.blank()
        let innerController = inner.contentViewController!
        inner.contentViewController = nil
        host.addChild(innerController)
        host.view.addSubview(innerController.view)
        let window = NSWindow(contentViewController: host)

        XCTAssertTrue(SidebarCollapseLock.apply(in: window))
        XCTAssertFalse(sidebar.canCollapse)
    }

    func testReportsMissingSplitViewSoCallerCanRetry() {
        let window = NSWindow(contentViewController: NSViewController.blank())
        XCTAssertFalse(SidebarCollapseLock.apply(in: window))
    }

    func testToggleStillCollapsesAndRestoresLockedSidebar() {
        let (window, sidebar, _, _) = makeWindow()
        SidebarCollapseLock.apply(in: window)

        sidebar.isCollapsed = true
        XCTAssertTrue(sidebar.isCollapsed, "View ▸ Toggle Sidebar must keep working")
        sidebar.isCollapsed = false
        XCTAssertFalse(sidebar.isCollapsed)
    }
}

private extension NSViewController {
    static func blank() -> NSViewController {
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        return controller
    }
}
