import XCTest
@testable import Victor

/// Tests for FileCacheManager - LRU content cache for file editing
@MainActor
final class FileCacheManagerTests: XCTestCase {

    // MARK: - Basic Content Storage Tests

    func testGetContentReturnsNilForUnknownNode() {
        let manager = FileCacheManager()
        let unknownID = UUID()

        XCTAssertNil(manager.getContent(for: unknownID))
    }

    func testSetAndGetContent() {
        let manager = FileCacheManager()
        let nodeID = UUID()
        let content = "# Hello World"

        manager.setContent(content, for: nodeID)

        XCTAssertEqual(manager.getContent(for: nodeID), content)
    }

    func testSetContentOverwritesPrevious() {
        let manager = FileCacheManager()
        let nodeID = UUID()

        manager.setContent("First", for: nodeID)
        manager.setContent("Second", for: nodeID)

        XCTAssertEqual(manager.getContent(for: nodeID), "Second")
    }

    func testMultipleNodesStoredIndependently() {
        let manager = FileCacheManager()
        let node1 = UUID()
        let node2 = UUID()
        let node3 = UUID()

        manager.setContent("Content 1", for: node1)
        manager.setContent("Content 2", for: node2)
        manager.setContent("Content 3", for: node3)

        XCTAssertEqual(manager.getContent(for: node1), "Content 1")
        XCTAssertEqual(manager.getContent(for: node2), "Content 2")
        XCTAssertEqual(manager.getContent(for: node3), "Content 3")
    }

    // MARK: - Clear Content Tests

    func testClearContentRemovesSpecificNode() {
        let manager = FileCacheManager()
        let node1 = UUID()
        let node2 = UUID()

        manager.setContent("Content 1", for: node1)
        manager.setContent("Content 2", for: node2)

        manager.clearContent(for: node1)

        XCTAssertNil(manager.getContent(for: node1))
        XCTAssertEqual(manager.getContent(for: node2), "Content 2")
    }

    func testClearAllContent() {
        let manager = FileCacheManager()
        let node1 = UUID()
        let node2 = UUID()

        manager.setContent("Content 1", for: node1)
        manager.setContent("Content 2", for: node2)

        manager.clearAll()

        XCTAssertNil(manager.getContent(for: node1))
        XCTAssertNil(manager.getContent(for: node2))
    }

    // MARK: - LRU Cache Order Tests

    func testMarkAccessedUpdatesOrder() {
        let manager = FileCacheManager(maxCachedFiles: 3)
        let node1 = UUID()
        let node2 = UUID()
        let node3 = UUID()

        // Add in order: 1, 2, 3
        manager.setContent("1", for: node1)
        manager.setContent("2", for: node2)
        manager.setContent("3", for: node3)

        // Access node1 again - should move to front
        manager.markAccessed(node1)

        // Order should now be: 1, 3, 2 (node1 at front)
        let order = manager.cacheOrder
        XCTAssertEqual(order.first, node1)
    }

    func testSetContentMarksAsAccessed() {
        let manager = FileCacheManager(maxCachedFiles: 3)
        let node1 = UUID()
        let node2 = UUID()

        manager.setContent("1", for: node1)
        manager.setContent("2", for: node2)
        // Set node1 again - should move to front
        manager.setContent("1 updated", for: node1)

        let order = manager.cacheOrder
        XCTAssertEqual(order.first, node1)
    }

    // MARK: - LRU Eviction Tests

    func testEvictionWhenOverLimit() {
        let manager = FileCacheManager(maxCachedFiles: 3)
        let node1 = UUID()
        let node2 = UUID()
        let node3 = UUID()
        let node4 = UUID()

        manager.setContent("1", for: node1)
        manager.setContent("2", for: node2)
        manager.setContent("3", for: node3)

        // All 3 should be present
        XCTAssertNotNil(manager.getContent(for: node1))
        XCTAssertNotNil(manager.getContent(for: node2))
        XCTAssertNotNil(manager.getContent(for: node3))

        // Add 4th - should trigger eviction of node1 (oldest)
        manager.setContent("4", for: node4)
        manager.evictIfNeeded(excluding: nil, modified: [])

        XCTAssertNil(manager.getContent(for: node1), "Oldest node should be evicted")
        XCTAssertNotNil(manager.getContent(for: node2))
        XCTAssertNotNil(manager.getContent(for: node3))
        XCTAssertNotNil(manager.getContent(for: node4))
    }

    func testEvictionSkipsSelectedNode() {
        let manager = FileCacheManager(maxCachedFiles: 2)
        let node1 = UUID()
        let node2 = UUID()
        let node3 = UUID()

        manager.setContent("1", for: node1)
        manager.setContent("2", for: node2)
        manager.setContent("3", for: node3)

        // node1 is the oldest, but we're excluding it (it's selected)
        manager.evictIfNeeded(excluding: node1, modified: [])

        // node1 should still exist because it's excluded
        XCTAssertNotNil(manager.getContent(for: node1))
        // node2 should be evicted instead (next oldest)
        XCTAssertNil(manager.getContent(for: node2))
        XCTAssertNotNil(manager.getContent(for: node3))
    }

    func testEvictionSkipsModifiedNodes() {
        let manager = FileCacheManager(maxCachedFiles: 2)
        let node1 = UUID()
        let node2 = UUID()
        let node3 = UUID()

        manager.setContent("1", for: node1)
        manager.setContent("2", for: node2)
        manager.setContent("3", for: node3)

        // node1 is oldest but modified, node2 is next oldest but also modified
        // node3 is newest and not modified - it will be evicted
        manager.evictIfNeeded(excluding: nil, modified: [node1, node2])

        // Modified nodes should still exist
        XCTAssertNotNil(manager.getContent(for: node1), "Modified node1 should not be evicted")
        XCTAssertNotNil(manager.getContent(for: node2), "Modified node2 should not be evicted")
        // node3 was the only evictable node
        XCTAssertNil(manager.getContent(for: node3), "Unprotected node3 should be evicted")
    }

    func testEvictionWithMixedProtectedNodes() {
        let manager = FileCacheManager(maxCachedFiles: 2)
        let selected = UUID()
        let modified = UUID()
        let normal1 = UUID()
        let normal2 = UUID()

        manager.setContent("selected", for: selected)
        manager.setContent("modified", for: modified)
        manager.setContent("normal1", for: normal1)
        manager.setContent("normal2", for: normal2)

        // Evict with selected and modified protected
        manager.evictIfNeeded(excluding: selected, modified: [modified])

        // Protected nodes should remain
        XCTAssertNotNil(manager.getContent(for: selected))
        XCTAssertNotNil(manager.getContent(for: modified))
        // At least one normal node should be evicted
        let normalCount = [normal1, normal2].filter { manager.getContent(for: $0) != nil }.count
        XCTAssertLessThanOrEqual(normalCount, 1)
    }

    func testEvictIfNeededTerminatesWhenAllEntriesProtected() {
        let manager = FileCacheManager(maxCachedFiles: 2)
        let node1 = UUID()
        let node2 = UUID()
        let node3 = UUID()

        manager.setContent("1", for: node1)
        manager.setContent("2", for: node2)
        manager.setContent("3", for: node3)

        // Over limit, but every entry is protected - must return without spinning forever
        let evicted = manager.evictIfNeeded(excluding: node3, modified: [node1, node2])

        XCTAssertTrue(evicted.isEmpty, "No protected entry may be evicted")
        XCTAssertNotNil(manager.getContent(for: node1))
        XCTAssertNotNil(manager.getContent(for: node2))
        XCTAssertNotNil(manager.getContent(for: node3))
    }

    // MARK: - Cache Count Tests

    func testCachedCountReflectsStoredItems() {
        let manager = FileCacheManager()

        XCTAssertEqual(manager.cachedCount, 0)

        manager.setContent("1", for: UUID())
        XCTAssertEqual(manager.cachedCount, 1)

        manager.setContent("2", for: UUID())
        XCTAssertEqual(manager.cachedCount, 2)
    }

    func testCachedCountAfterClear() {
        let manager = FileCacheManager()
        let node = UUID()

        manager.setContent("content", for: node)
        XCTAssertEqual(manager.cachedCount, 1)

        manager.clearContent(for: node)
        XCTAssertEqual(manager.cachedCount, 0)
    }

    // MARK: - Has Content Tests

    func testHasContent() {
        let manager = FileCacheManager()
        let node = UUID()

        XCTAssertFalse(manager.hasContent(for: node))

        manager.setContent("content", for: node)
        XCTAssertTrue(manager.hasContent(for: node))

        manager.clearContent(for: node)
        XCTAssertFalse(manager.hasContent(for: node))
    }
}
