import Foundation
import AppKit

/// Service for managing and loading assets from static/ and assets/ directories
actor AssetService {
    static let shared = AssetService()

    private var thumbnailCache: [URL: NSImage] = [:]
    private let thumbnailSize = CGSize(width: 120, height: 120)

    // MARK: - Scanning

    /// Scan a directory for assets
    func scanAssets(in directory: URL, isAssetsDir: Bool) async throws -> [Asset] {
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

        var assets: [Asset] = []

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

            let asset = Asset(url: url, relativePath: relativePath, isInAssetsDir: isAssetsDir)
            assets.append(asset)
        }

        return assets
    }

    /// Scan both static/ and assets/ directories
    func scanAllAssets(siteURL: URL) async throws -> [Asset] {
        var allAssets: [Asset] = []

        // Scan static/
        let staticURL = siteURL.appendingPathComponent("static")
        if FileManager.default.fileExists(atPath: staticURL.path) {
            let staticAssets = try await scanAssets(in: staticURL, isAssetsDir: false)
            allAssets.append(contentsOf: staticAssets)
        }

        // Scan assets/
        let assetsURL = siteURL.appendingPathComponent("assets")
        if FileManager.default.fileExists(atPath: assetsURL.path) {
            let pipeAssets = try await scanAssets(in: assetsURL, isAssetsDir: true)
            allAssets.append(contentsOf: pipeAssets)
        }

        return allAssets
    }

    // MARK: - Metadata Loading

    /// Load metadata for an asset (file size, modification date, dimensions)
    func loadAssetMetadata(_ asset: Asset) async {
        guard !asset.isMetadataLoaded else { return }

        let fm = FileManager.default

        // Load file attributes
        if let attributes = try? fm.attributesOfItem(atPath: asset.url.path) {
            await MainActor.run {
                asset.fileSize = attributes[.size] as? Int64
                asset.modificationDate = attributes[.modificationDate] as? Date
            }
        }

        // Load image dimensions and thumbnail for images
        if asset.fileType == .image {
            if let image = NSImage(contentsOf: asset.url) {
                let dims = image.size
                let thumb = await generateThumbnail(for: image)

                await MainActor.run {
                    asset.dimensions = dims
                    asset.thumbnail = thumb
                }
            }
        }

        await MainActor.run {
            asset.isMetadataLoaded = true
        }
    }

    /// Load metadata for multiple assets
    func loadMetadataForAssets(_ assets: [Asset]) async {
        // Process in batches to avoid overwhelming the system
        let batchSize = 10

        for batchStart in stride(from: 0, to: assets.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, assets.count)
            let batch = Array(assets[batchStart..<batchEnd])

            await withTaskGroup(of: Void.self) { group in
                for asset in batch {
                    group.addTask {
                        await self.loadAssetMetadata(asset)
                    }
                }
            }
        }
    }

    // MARK: - Thumbnail Generation

    /// Generate a thumbnail for an image
    private func generateThumbnail(for image: NSImage) async -> NSImage {
        // Check cache first
        // Note: We can't cache by URL in actor since we don't have it here
        // The caching happens at a higher level

        let aspectRatio = image.size.width / image.size.height
        var thumbSize = thumbnailSize

        if aspectRatio > 1 {
            thumbSize.height = thumbSize.width / aspectRatio
        } else {
            thumbSize.width = thumbSize.height * aspectRatio
        }

        // Ensure minimum size
        thumbSize.width = max(thumbSize.width, 1)
        thumbSize.height = max(thumbSize.height, 1)

        let thumbnail = NSImage(size: thumbSize)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: thumbSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        thumbnail.unlockFocus()

        return thumbnail
    }

    /// Get cached thumbnail or generate one
    func getThumbnail(for asset: Asset) async -> NSImage? {
        // Check cache
        if let cached = thumbnailCache[asset.url] {
            return cached
        }

        guard asset.fileType == .image,
              let image = NSImage(contentsOf: asset.url) else {
            return nil
        }

        let thumbnail = await generateThumbnail(for: image)
        thumbnailCache[asset.url] = thumbnail

        return thumbnail
    }

    // MARK: - Cache Management

    /// Clear the thumbnail cache
    func clearThumbnailCache() {
        thumbnailCache.removeAll()
    }

    /// Remove a specific URL from cache
    func invalidateThumbnail(for url: URL) {
        thumbnailCache.removeValue(forKey: url)
    }
}
