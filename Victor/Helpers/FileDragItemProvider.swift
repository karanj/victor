import AppKit
import Foundation

/// Builds an `NSItemProvider` for dragging a file out to Finder or another app.
/// `NSItemProvider(contentsOf:)` registers the `public.file-url` representation, which is
/// what makes a Finder drop perform a real copy - unlike `.draggable(url)`, whose
/// `Transferable` conformance exports a plain `absoluteString`.
enum FileDragItemProvider {
    /// - Parameters:
    ///   - url: the file/folder to drag, registered via `contentsOf:`.
    ///   - secondaryRepresentation: an optional string registered alongside, so a drop
    ///     into a plain-text context yields something better than a raw `file://` URL -
    ///     the asset browser's markdown syntax, or the sidebar's plain path.
    static func make(for url: URL, secondaryRepresentation: String? = nil) -> NSItemProvider {
        let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
        if let secondaryRepresentation {
            provider.registerObject(secondaryRepresentation as NSString, visibility: .all)
        }
        return provider
    }
}
