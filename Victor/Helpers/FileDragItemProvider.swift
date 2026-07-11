import AppKit
import Foundation

/// Builds an `NSItemProvider` for dragging a file out of Victor to Finder or
/// another app. `NSItemProvider(contentsOf:)` registers the file URL /
/// `public.file-url` representation - the thing that makes a drop on Finder
/// perform a real file copy, matching Finder's own drag behavior (as opposed
/// to `.draggable(url)`'s `Transferable` conformance, which exports a plain
/// `absoluteString` and loses that).
///
/// Extracted (victor-sel B.4) from `AssetBrowserView.assetDragItemProvider`
/// so the sidebar's drag source and the asset browser's drag source share one
/// implementation instead of two copies of the same three lines.
enum FileDragItemProvider {
    /// - Parameters:
    ///   - url: the file/folder to drag - registered via `contentsOf:` so a
    ///     drop on Finder performs a real copy.
    ///   - secondaryRepresentation: an optional second string representation
    ///     registered alongside the file URL, so a drop into a plain-text
    ///     context (a text editor, Terminal, the markdown editor itself)
    ///     yields something more useful than a raw `file://` URL - e.g. the
    ///     asset browser's markdown-image syntax, or the sidebar's plain
    ///     path string (mirroring `copyPathsToClipboard`).
    static func make(for url: URL, secondaryRepresentation: String? = nil) -> NSItemProvider {
        let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
        if let secondaryRepresentation {
            provider.registerObject(secondaryRepresentation as NSString, visibility: .all)
        }
        return provider
    }
}
