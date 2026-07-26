import XCTest
import CoreGraphics
@testable import Victor

/// Tests for the two pure helpers behind the Advanced-tab layout unification:
/// `DataValueSummary` (a container row's child count) and
/// `WrappingHStackLine.breakIntoLines` (the greedy line breaker behind `WrappingHStack`).
final class DataValueSummaryTests: XCTestCase {

    // MARK: - Dictionaries

    func testDictionarySummaryPluralizes() {
        XCTAssertEqual(DataValueSummary.text(for: ["a": 1, "b": 2] as [String: Any]), "2 fields")
    }

    func testDictionarySummarySingularForOneField() {
        XCTAssertEqual(DataValueSummary.text(for: ["a": 1] as [String: Any]), "1 field")
    }

    func testEmptyDictionarySummaryIsPlural() {
        XCTAssertEqual(DataValueSummary.text(for: [String: Any]()), "0 fields")
    }

    // MARK: - Arrays

    func testArraySummaryPluralizes() {
        XCTAssertEqual(DataValueSummary.text(for: [1, 2, 3] as [Any]), "3 items")
    }

    func testArraySummarySingularForOneItem() {
        XCTAssertEqual(DataValueSummary.text(for: [1] as [Any]), "1 item")
    }

    // MARK: - Scalars

    /// Scalars never render a disclosure header, so they have no summary —
    /// an empty string rather than a misleading "0 fields".
    func testScalarSummaryIsEmpty() {
        XCTAssertEqual(DataValueSummary.text(for: "hello"), "")
        XCTAssertEqual(DataValueSummary.text(for: 42), "")
        XCTAssertEqual(DataValueSummary.text(for: true), "")
    }
}

final class WrappingHStackLineTests: XCTestCase {

    private func sizes(_ widths: [CGFloat], height: CGFloat = 20) -> [CGSize] {
        widths.map { CGSize(width: $0, height: height) }
    }

    private func lines(_ widths: [CGFloat], maxWidth: CGFloat, spacing: CGFloat = 4) -> [WrappingHStackLine] {
        WrappingHStackLine.breakIntoLines(sizes: sizes(widths), maxWidth: maxWidth, spacing: spacing)
    }

    // MARK: - Fitting on one line

    func testEverythingFitsOnOneLine() {
        let result = lines([50, 50, 50], maxWidth: 300)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].range, 0..<3)
        XCTAssertEqual(result[0].width, 158) // 150 + 2 gaps of 4
    }

    func testEmptyInputProducesNoLines() {
        XCTAssertTrue(lines([], maxWidth: 300).isEmpty)
    }

    // MARK: - Wrapping

    /// The regression this layout exists for: an `HStack` would have
    /// compressed all four chips onto one line; the flow layout wraps.
    func testWrapsWhenNextSubviewWouldOverrun() {
        let result = lines([100, 100, 100, 100], maxWidth: 250)
        XCTAssertEqual(result.map(\.range), [0..<2, 2..<4])
    }

    func testSpacingCountsTowardOverrun() {
        // 3 x 100 = 300 fits exactly in 300, but two 4pt gaps push it to 308.
        let result = lines([100, 100, 100], maxWidth: 300, spacing: 4)
        XCTAssertEqual(result.map(\.range), [0..<2, 2..<3])
    }

    func testZeroSpacingPacksExactlyToWidth() {
        let result = lines([100, 100, 100], maxWidth: 300, spacing: 0)
        XCTAssertEqual(result.map(\.range), [0..<3])
    }

    // MARK: - Degenerate input

    /// A single chip wider than the container gets its own line rather than
    /// producing an empty line or looping forever.
    func testOversizedSubviewGetsItsOwnLine() {
        let result = lines([500, 40], maxWidth: 100)
        XCTAssertEqual(result.map(\.range), [0..<1, 1..<2])
        XCTAssertEqual(result[0].width, 500)
    }

    func testConsecutiveOversizedSubviewsEachGetALine() {
        let result = lines([500, 500], maxWidth: 100)
        XCTAssertEqual(result.map(\.range), [0..<1, 1..<2])
    }

    // MARK: - Line height

    /// A line's height is the tallest subview on that line, so rows with
    /// mixed-height chips don't clip.
    func testLineHeightIsTallestSubviewOnThatLine() {
        let mixed = [
            CGSize(width: 40, height: 20),
            CGSize(width: 40, height: 34),
            CGSize(width: 40, height: 20)
        ]
        let result = WrappingHStackLine.breakIntoLines(sizes: mixed, maxWidth: 500, spacing: 4)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].height, 34)
    }

    func testHeightsAreTrackedPerLineNotGlobally() {
        let mixed = [
            CGSize(width: 80, height: 40),
            CGSize(width: 80, height: 12)
        ]
        let result = WrappingHStackLine.breakIntoLines(sizes: mixed, maxWidth: 100, spacing: 4)
        XCTAssertEqual(result.map(\.height), [40, 12])
    }

    // MARK: - Coverage

    /// Every subview lands on exactly one line — no drops, no duplicates.
    func testLinesPartitionAllSubviews() {
        let widths: [CGFloat] = [30, 90, 20, 140, 60, 110, 45]
        let result = lines(widths, maxWidth: 200)
        let covered = result.flatMap { Array($0.range) }
        XCTAssertEqual(covered, Array(0..<widths.count))
    }
}
