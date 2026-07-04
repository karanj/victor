import Foundation
import AppKit

/// Sendable wire format for a scanned file, crossing the actor boundary in place
/// of the non-Sendable `Asset` class (which is `@Observable` and bound directly
/// into `AssetBrowserView`/`AssetDetailPanel` - it stays a class). The
/// `@MainActor` caller constructs `Asset` instances from these (WP3.5 Cluster 5).
struct AssetDescriptor: Sendable {
    let url: URL
    let relativePath: String
    let isInAssetsDir: Bool
}

/// Sendable wire format for `metadataSnapshot(for:)`'s result. `thumbnail` is
/// deliberately excluded - `NSImage` isn't `Sendable`, and thumbnail generation
/// stays on the main actor (see `AssetBrowserView`'s `generateThumbnail(for:)`).
struct AssetMetadataSnapshot: Sendable {
    let fileSize: Int64?
    let modificationDate: Date?
    let dimensions: CGSize?
}

/// Service for managing and loading assets from static/ and assets/ directories
actor AssetService {
    static let shared = AssetService()

    // MARK: - Scanning

    /// Scan a directory for assets, returning Sendable descriptors rather than
    /// `Asset` instances - the `@MainActor` caller constructs `Asset`s from these.
    func scanAssets(in directory: URL, isAssetsDir: Bool) async throws -> [AssetDescriptor] {
        let fm = FileManager.default

        guard fm.fileExists(atPath: directory.path) else {
            return []
        }

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        // Collect URLs synchronously to avoid Swift 6 async iterator warning
        var urls: [URL] = []
        while let element = enumerator.nextObject() {
            if let url = element as? URL {
                urls.append(url)
            }
        }

        var descriptors: [AssetDescriptor] = []

        for url in urls {
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues?.isDirectory == false else { continue }

            // Skip hidden files and common non-asset files
            let filename = url.lastPathComponent
            guard !filename.hasPrefix("."),
                  !filename.hasSuffix(".DS_Store") else { continue }

            let relativePath = url.path.replacingOccurrences(
                of: directory.path + "/",
                with: ""
            )

            descriptors.append(AssetDescriptor(url: url, relativePath: relativePath, isInAssetsDir: isAssetsDir))
        }

        return descriptors
    }

    /// Scan both static/ and assets/ directories
    func scanAllAssets(siteURL: URL) async throws -> [AssetDescriptor] {
        var allDescriptors: [AssetDescriptor] = []

        // Scan static/
        let staticURL = siteURL.appendingPathComponent("static")
        if FileManager.default.fileExists(atPath: staticURL.path) {
            let staticDescriptors = try await scanAssets(in: staticURL, isAssetsDir: false)
            allDescriptors.append(contentsOf: staticDescriptors)
        }

        // Scan assets/
        let assetsURL = siteURL.appendingPathComponent("assets")
        if FileManager.default.fileExists(atPath: assetsURL.path) {
            let pipeDescriptors = try await scanAssets(in: assetsURL, isAssetsDir: true)
            allDescriptors.append(contentsOf: pipeDescriptors)
        }

        return allDescriptors
    }

    // MARK: - Metadata Loading

    /// Load metadata (file size, modification date, image dimensions) for a single file.
    /// Actor-only: reads `FileManager`/`NSImage` (just for `.size`, not to draw a
    /// thumbnail) and returns a Sendable snapshot - no `Asset` parameter, no
    /// `MainActor.run` hop. The `!asset.isMetadataLoaded` de-dup guard that used to
    /// live here now lives at the `@MainActor` call site, before invoking this
    /// (WP3.5 Cluster 5 - this changes *where* duplicate-load prevention happens).
    func metadataSnapshot(for url: URL) async -> AssetMetadataSnapshot? {
        let fm = FileManager.default

        var fileSize: Int64?
        var modificationDate: Date?
        if let attributes = try? fm.attributesOfItem(atPath: url.path) {
            fileSize = attributes[.size] as? Int64
            modificationDate = attributes[.modificationDate] as? Date
        }

        var dimensions: CGSize?
        if FileType(url: url) == .image, let image = NSImage(contentsOf: url) {
            dimensions = image.size
        }

        guard fileSize != nil || modificationDate != nil || dimensions != nil else {
            return nil
        }

        return AssetMetadataSnapshot(fileSize: fileSize, modificationDate: modificationDate, dimensions: dimensions)
    }

    /// Load metadata snapshots for multiple URLs, keyed by URL for the caller to
    /// apply back onto its `Asset` instances. Same batching as before.
    func metadataSnapshots(for urls: [URL]) async -> [URL: AssetMetadataSnapshot] {
        // Process in batches to avoid overwhelming the system
        let batchSize = 10
        var results: [URL: AssetMetadataSnapshot] = [:]

        for batchStart in stride(from: 0, to: urls.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, urls.count)
            let batch = Array(urls[batchStart..<batchEnd])

            await withTaskGroup(of: (URL, AssetMetadataSnapshot?).self) { group in
                for url in batch {
                    group.addTask {
                        (url, await self.metadataSnapshot(for: url))
                    }
                }
                for await (url, snapshot) in group {
                    if let snapshot {
                        results[url] = snapshot
                    }
                }
            }
        }

        return results
    }
}
