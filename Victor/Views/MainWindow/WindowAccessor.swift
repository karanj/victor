import SwiftUI
import AppKit

/// Bridges to the hosting `NSWindow` for the handful of window-level APIs SwiftUI
/// doesn't expose (e.g. `isDocumentEdited`).
///
/// This is THE single AppKit window bridge for the app. Future NSWindow needs
/// should hang off this one accessor rather than introducing another
/// `NSViewRepresentable` — see the "AppKit bridge inventory" in
/// Docs/MAC-POLISH-DESIGN.md.
///
/// Usage: attach as an invisible view so it mounts into the same view
/// hierarchy as the content it's tracking, e.g.
/// `.background(WindowAccessor { window in ... })`.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        TrackingView(onWindow: onWindow)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Zero-size NSView whose sole job is reporting `window` as soon as it's
    /// attached to one, and again on every subsequent change (window can be
    /// nil transiently during SwiftUI view updates).
    private final class TrackingView: NSView {
        let onWindow: (NSWindow) -> Void

        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onWindow(window)
            }
        }
    }
}
