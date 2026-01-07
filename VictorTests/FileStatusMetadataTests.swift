import XCTest
@testable import Victor

/// Tests for FileStatusMetadata status computations
final class FileStatusMetadataTests: XCTestCase {

    // MARK: - Single Status Tests

    /// Test that a published post (no draft, no future date, no expiry) returns no statuses
    func testPublishedPostReturnsNoStatuses() {
        let metadata = FileStatusMetadata(
            isDraft: false,
            date: Date().addingTimeInterval(-86400), // Yesterday
            publishDate: nil,
            expiryDate: nil
        )

        XCTAssertTrue(metadata.statuses.isEmpty)
        XCTAssertEqual(metadata.status, .published)
    }

    /// Test that a draft post returns draft status
    func testDraftPostReturnsDraftStatus() {
        let metadata = FileStatusMetadata(
            isDraft: true,
            date: Date().addingTimeInterval(-86400), // Yesterday
            publishDate: nil,
            expiryDate: nil
        )

        XCTAssertEqual(metadata.statuses, [.draft])
        XCTAssertEqual(metadata.status, .draft)
    }

    /// Test that a future-dated post returns scheduled status
    func testFutureDatedPostReturnsScheduledStatus() {
        let metadata = FileStatusMetadata(
            isDraft: false,
            date: Date().addingTimeInterval(86400 * 7), // Next week
            publishDate: nil,
            expiryDate: nil
        )

        XCTAssertEqual(metadata.statuses, [.scheduled])
        XCTAssertEqual(metadata.status, .scheduled)
    }

    /// Test that a post with future publishDate returns scheduled status
    func testFuturePublishDateReturnsScheduledStatus() {
        let metadata = FileStatusMetadata(
            isDraft: false,
            date: Date().addingTimeInterval(-86400), // Yesterday
            publishDate: Date().addingTimeInterval(86400 * 7), // Next week
            expiryDate: nil
        )

        XCTAssertEqual(metadata.statuses, [.scheduled])
        XCTAssertEqual(metadata.status, .scheduled)
    }

    /// Test that an expired post returns expired status
    func testExpiredPostReturnsExpiredStatus() {
        let metadata = FileStatusMetadata(
            isDraft: false,
            date: Date().addingTimeInterval(-86400 * 30), // Month ago
            publishDate: nil,
            expiryDate: Date().addingTimeInterval(-86400) // Yesterday
        )

        XCTAssertEqual(metadata.statuses, [.expired])
        XCTAssertEqual(metadata.status, .expired)
    }

    // MARK: - Multiple Status Tests

    /// Test that a draft AND future-dated post returns both statuses
    func testDraftAndScheduledReturnsMultipleStatuses() {
        let metadata = FileStatusMetadata(
            isDraft: true,
            date: Date().addingTimeInterval(86400 * 7), // Next week
            publishDate: nil,
            expiryDate: nil
        )

        XCTAssertEqual(metadata.statuses.count, 2)
        XCTAssertTrue(metadata.statuses.contains(.draft))
        XCTAssertTrue(metadata.statuses.contains(.scheduled))
        // First status should be draft (order: draft, scheduled, expired)
        XCTAssertEqual(metadata.status, .draft)
    }

    /// Test that a draft AND expired post returns both statuses
    func testDraftAndExpiredReturnsMultipleStatuses() {
        let metadata = FileStatusMetadata(
            isDraft: true,
            date: Date().addingTimeInterval(-86400 * 30), // Month ago
            publishDate: nil,
            expiryDate: Date().addingTimeInterval(-86400) // Yesterday
        )

        XCTAssertEqual(metadata.statuses.count, 2)
        XCTAssertTrue(metadata.statuses.contains(.draft))
        XCTAssertTrue(metadata.statuses.contains(.expired))
        XCTAssertEqual(metadata.status, .draft)
    }

    /// Test extreme case: draft, scheduled, AND expired (unlikely but possible)
    func testDraftScheduledAndExpiredReturnsAllStatuses() {
        // This is a weird edge case: a draft post with a future date but also expired
        // In practice this shouldn't happen, but the code should handle it
        let metadata = FileStatusMetadata(
            isDraft: true,
            date: Date().addingTimeInterval(86400 * 7), // Next week
            publishDate: nil,
            expiryDate: Date().addingTimeInterval(-86400) // Yesterday (expired)
        )

        XCTAssertEqual(metadata.statuses.count, 3)
        XCTAssertTrue(metadata.statuses.contains(.draft))
        XCTAssertTrue(metadata.statuses.contains(.scheduled))
        XCTAssertTrue(metadata.statuses.contains(.expired))
    }

    // MARK: - Status Order Tests

    /// Test that statuses are returned in consistent order: draft, scheduled, expired
    func testStatusOrderIsConsistent() {
        let metadata = FileStatusMetadata(
            isDraft: true,
            date: Date().addingTimeInterval(86400 * 7), // Next week
            publishDate: nil,
            expiryDate: Date().addingTimeInterval(-86400) // Yesterday
        )

        let statuses = metadata.statuses
        XCTAssertEqual(statuses[0], .draft)
        XCTAssertEqual(statuses[1], .scheduled)
        XCTAssertEqual(statuses[2], .expired)
    }

    // MARK: - Edge Cases

    /// Test nil date fields
    func testNilDateFieldsReturnsNoStatuses() {
        let metadata = FileStatusMetadata(
            isDraft: false,
            date: nil,
            publishDate: nil,
            expiryDate: nil
        )

        XCTAssertTrue(metadata.statuses.isEmpty)
        XCTAssertEqual(metadata.status, .published)
    }

    /// Test draft with nil dates
    func testDraftWithNilDatesReturnsDraft() {
        let metadata = FileStatusMetadata(
            isDraft: true,
            date: nil,
            publishDate: nil,
            expiryDate: nil
        )

        XCTAssertEqual(metadata.statuses, [.draft])
        XCTAssertEqual(metadata.status, .draft)
    }

    /// Test publishDate takes precedence over date for scheduling
    func testPublishDateTakesPrecedenceOverDate() {
        // date is in the past, but publishDate is in the future
        let metadata = FileStatusMetadata(
            isDraft: false,
            date: Date().addingTimeInterval(-86400), // Yesterday
            publishDate: Date().addingTimeInterval(86400), // Tomorrow
            expiryDate: nil
        )

        XCTAssertEqual(metadata.statuses, [.scheduled])
    }

    /// Test current moment boundary (date exactly now)
    func testCurrentMomentBoundary() {
        let now = Date()
        let metadata = FileStatusMetadata(
            isDraft: false,
            date: now,
            publishDate: nil,
            expiryDate: nil
        )

        // Date at exactly now should not be scheduled (not > now)
        XCTAssertTrue(metadata.statuses.isEmpty)
    }

    // MARK: - Frontmatter Integration Tests

    /// Test creating FileStatusMetadata from Frontmatter
    func testInitFromFrontmatter() {
        let frontmatter = Frontmatter(rawContent: "", format: .yaml)
        frontmatter.isDraft = true
        frontmatter.date = Date().addingTimeInterval(86400 * 7)

        let metadata = FileStatusMetadata(from: frontmatter)

        XCTAssertTrue(metadata.isDraft)
        XCTAssertNotNil(metadata.date)
        XCTAssertEqual(metadata.statuses.count, 2)
        XCTAssertTrue(metadata.statuses.contains(.draft))
        XCTAssertTrue(metadata.statuses.contains(.scheduled))
    }

    /// Test creating FileStatusMetadata from nil Frontmatter
    func testInitFromNilFrontmatter() {
        let metadata = FileStatusMetadata(from: nil)

        XCTAssertFalse(metadata.isDraft)
        XCTAssertNil(metadata.date)
        XCTAssertNil(metadata.publishDate)
        XCTAssertNil(metadata.expiryDate)
        XCTAssertTrue(metadata.statuses.isEmpty)
    }

    // MARK: - Mutation Tests

    /// Test that changing frontmatter values updates the badge list
    func testFrontmatterChangesUpdateStatuses() {
        let frontmatter = Frontmatter(rawContent: "", format: .yaml)
        frontmatter.isDraft = false
        frontmatter.date = Date().addingTimeInterval(-86400) // Yesterday (published)

        // Initial state: published post, no badges
        var metadata = FileStatusMetadata(from: frontmatter)
        XCTAssertTrue(metadata.statuses.isEmpty, "Published post should have no statuses")

        // Change 1: Mark as draft
        frontmatter.isDraft = true
        metadata = FileStatusMetadata(from: frontmatter)
        XCTAssertEqual(metadata.statuses, [.draft], "Draft post should show draft badge")

        // Change 2: Also schedule for future
        frontmatter.date = Date().addingTimeInterval(86400 * 7) // Next week
        metadata = FileStatusMetadata(from: frontmatter)
        XCTAssertEqual(metadata.statuses.count, 2, "Draft + scheduled should show 2 badges")
        XCTAssertTrue(metadata.statuses.contains(.draft))
        XCTAssertTrue(metadata.statuses.contains(.scheduled))

        // Change 3: Unmark draft, keep scheduled
        frontmatter.isDraft = false
        metadata = FileStatusMetadata(from: frontmatter)
        XCTAssertEqual(metadata.statuses, [.scheduled], "Scheduled-only post should show scheduled badge")

        // Change 4: Move date to past (becomes published)
        frontmatter.date = Date().addingTimeInterval(-86400)
        metadata = FileStatusMetadata(from: frontmatter)
        XCTAssertTrue(metadata.statuses.isEmpty, "Past-dated non-draft should be published")

        // Change 5: Add expiry date in the past
        frontmatter.expiryDate = Date().addingTimeInterval(-3600) // 1 hour ago
        metadata = FileStatusMetadata(from: frontmatter)
        XCTAssertEqual(metadata.statuses, [.expired], "Expired post should show expired badge")

        // Change 6: Mark as draft again (draft + expired)
        frontmatter.isDraft = true
        metadata = FileStatusMetadata(from: frontmatter)
        XCTAssertEqual(metadata.statuses.count, 2, "Draft + expired should show 2 badges")
        XCTAssertTrue(metadata.statuses.contains(.draft))
        XCTAssertTrue(metadata.statuses.contains(.expired))
    }
}
