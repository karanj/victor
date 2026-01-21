import Foundation

/// Manages LRU caching of edited file content
///
/// Tracks edited content per file node and manages cache eviction
/// to prevent memory bloat when many files are opened.
@MainActor
final class FileCacheManager {
    /// Per-file edited content storage
    /// Key is file node ID, value is the edited content
    private var contentByFile: [UUID: String] = [:]

    /// LRU cache tracking: ordered list of node IDs (most recent first)
    private var _cacheOrder: [UUID] = []

    /// Maximum number of files to keep cached
    private let maxCachedFiles: Int

    /// Default maximum cached files
    /// Edited content strings are lightweight, so we can cache many
    private static let defaultMaxCachedFiles = 100

    /// Callback invoked when a node is evicted from cache
    /// Parameter is the evicted node ID
    var onEviction: ((UUID) -> Void)?

    /// Initialize with optional custom cache limit
    init(maxCachedFiles: Int = FileCacheManager.defaultMaxCachedFiles) {
        self.maxCachedFiles = maxCachedFiles
    }

    // MARK: - Content Access

    /// Get edited content for a file by node ID
    /// - Parameter nodeID: The file node's UUID
    /// - Returns: The cached content, or nil if not cached
    func getContent(for nodeID: UUID) -> String? {
        return contentByFile[nodeID]
    }

    /// Set edited content for a file by node ID
    /// - Parameters:
    ///   - content: The content to cache
    ///   - nodeID: The file node's UUID
    func setContent(_ content: String, for nodeID: UUID) {
        contentByFile[nodeID] = content
        markAccessed(nodeID)
    }

    /// Check if content exists for a node
    func hasContent(for nodeID: UUID) -> Bool {
        return contentByFile[nodeID] != nil
    }

    /// Number of cached files
    var cachedCount: Int {
        return contentByFile.count
    }

    /// Current cache order (exposed for testing)
    var cacheOrder: [UUID] {
        return _cacheOrder
    }

    // MARK: - Cache Management

    /// Mark a node as recently accessed (moves to front of LRU)
    func markAccessed(_ nodeID: UUID) {
        _cacheOrder.removeAll { $0 == nodeID }
        _cacheOrder.insert(nodeID, at: 0)
    }

    /// Clear content for a specific node
    func clearContent(for nodeID: UUID) {
        contentByFile.removeValue(forKey: nodeID)
        _cacheOrder.removeAll { $0 == nodeID }
    }

    /// Clear all cached content
    func clearAll() {
        contentByFile.removeAll()
        _cacheOrder.removeAll()
    }

    /// Evict old entries if over the cache limit
    /// - Parameters:
    ///   - excluding: Node ID to never evict (typically the selected node)
    ///   - modified: Set of node IDs with unsaved changes (never evict these)
    /// - Returns: Array of evicted node IDs (for logging or cleanup)
    @discardableResult
    func evictIfNeeded(excluding selectedID: UUID?, modified modifiedIDs: Set<UUID>) -> [UUID] {
        var evicted: [UUID] = []

        while _cacheOrder.count > maxCachedFiles {
            guard let oldestID = _cacheOrder.last else { break }

            // Don't evict selected node
            if oldestID == selectedID {
                // Move to front and try next
                _cacheOrder.removeLast()
                _cacheOrder.insert(oldestID, at: 0)
                continue
            }

            // Don't evict modified nodes
            if modifiedIDs.contains(oldestID) {
                // Move to front and try next
                _cacheOrder.removeLast()
                _cacheOrder.insert(oldestID, at: 0)
                continue
            }

            // Evict this node
            _cacheOrder.removeLast()
            contentByFile.removeValue(forKey: oldestID)
            evicted.append(oldestID)
            onEviction?(oldestID)
        }

        return evicted
    }
}
