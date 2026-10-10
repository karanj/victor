import AppKit

/// Stops the sidebar collapsing when its divider is dragged past the minimum width.
///
/// SwiftUI has no API for this: `NavigationSplitView` is backed by an
/// `NSSplitViewController` whose sidebar item defaults to `canCollapse = true`, and a
/// drag-collapsed sidebar leaves no divider to drag it back (dragging the window edge
/// resizes the window). Locking the item keeps drag-resizing within
/// `AppConstants.Sidebar` min/max; View ▸ Toggle Sidebar still collapses it, because
/// `canCollapse` gates user collapse only, not `isCollapsed`.
enum SidebarCollapseLock {
    /// Locks every sidebar item in `window`. Returns false when no split view
    /// controller is in the hierarchy yet, so the caller can retry after layout.
    @MainActor @discardableResult
    static func apply(in window: NSWindow) -> Bool {
        guard let root = window.contentView else { return false }
        let sidebars = splitViewControllers(under: root)
            .flatMap(\.splitViewItems)
            .filter { $0.behavior == .sidebar }
        for item in sidebars where item.canCollapse {
            item.canCollapse = false  // also resets canCollapseFromWindowResize
        }
        return !sidebars.isEmpty
    }

    @MainActor
    private static func splitViewControllers(under view: NSView) -> [NSSplitViewController] {
        var found: [NSSplitViewController] = []
        if let splitView = view as? NSSplitView,
           let controller = splitView.delegate as? NSSplitViewController {
            found.append(controller)
        }
        for subview in view.subviews {
            found += splitViewControllers(under: subview)
        }
        return found
    }
}
