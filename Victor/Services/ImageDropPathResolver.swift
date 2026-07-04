import Foundation

/// Resolves where a dropped/imported image file should be copied to within a Hugo
/// site, and how it should be referenced from markdown once it's there.
///
/// Mirrors the convention already encoded in `Asset.markdownSyntax` for existing
/// static/assets files (`isInAssetsDir ? relativePath : "/\(relativePath)"`), extended
/// with the page-bundle case: an image dropped while editing a file that lives inside
/// a Hugo page bundle (e.g. `content/posts/my-post/index.md`) is copied alongside that
/// bundle as a Hugo "page resource" and referenced by bare filename, rather than being
/// copied to `static/` and referenced root-relatively.
///
/// This is pure/deterministic path logic - no file I/O - so it's unit-testable without
/// touching disk. `FileSystemService.importFile` performs the actual copy using the
/// `directory` this resolves to.
enum ImageDropPathResolver {
    /// Where a dropped file should be copied, and how to build its markdown reference
    /// once the copy has produced a final (possibly de-duplicated) filename.
    struct Destination: Equatable {
        /// Directory the dropped file should be copied into.
        let directory: URL
        /// Markdown path style used to build the `![alt](path)` reference.
        let style: PathStyle
    }

    enum PathStyle: Equatable {
        /// Page resource: referenced by bare filename, relative to the page bundle.
        case pageBundleRelative
        /// static/ is served at the site root: referenced with a leading slash.
        case siteRootRelative

        /// Build the markdown-reference path for a final filename.
        func path(for filename: String) -> String {
            switch self {
            case .pageBundleRelative:
                return filename
            case .siteRootRelative:
                return "/\(filename)"
            }
        }
    }

    /// - Parameters:
    ///   - currentFileParentURL: the directory the file being edited lives in (its
    ///     `FileNode.parent?.url`), or nil if unknown/at the site root.
    ///   - parentIsPageBundle: whether `currentFileParentURL` is a Hugo page bundle
    ///     folder (`FileNode.parent?.isPageBundle`).
    ///   - siteRoot: the site's root URL.
    static func destination(
        currentFileParentURL: URL?,
        parentIsPageBundle: Bool,
        siteRoot: URL
    ) -> Destination {
        if parentIsPageBundle, let bundleURL = currentFileParentURL {
            return Destination(directory: bundleURL, style: .pageBundleRelative)
        }
        let staticURL = siteRoot.appendingPathComponent("static")
        return Destination(directory: staticURL, style: .siteRootRelative)
    }

    /// Build the full markdown image reference (`![alt](path)`) for a file that has
    /// just been copied to `destinationURL` (the URL returned by
    /// `FileSystemService.importFile`, whose filename may differ from the original
    /// due to collision avoidance).
    static func markdownImageReference(for destinationURL: URL, style: PathStyle) -> String {
        let altText = destinationURL.deletingPathExtension().lastPathComponent
        return "![\(altText)](\(style.path(for: destinationURL.lastPathComponent)))"
    }
}
