import XCTest
@testable import Victor

/// Tests for Hugo server related services
final class HugoServerTests: XCTestCase {

    // MARK: - BuildErrorParser Tests

    func testParseErrorWithFilePath() {
        let line = "ERROR 2024/01/15 10:30:00 Error building site: \"/path/to/file.html:42:13\": parse error"

        let error = BuildErrorParser.parseLine(line)

        XCTAssertNotNil(error)
        XCTAssertEqual(error?.level, .error)
    }

    func testParseWarning() {
        let line = "WARN 2024/01/15 10:30:00 found no layout file for \"page\" for kind \"page\""

        let error = BuildErrorParser.parseLine(line)

        XCTAssertNotNil(error)
        XCTAssertEqual(error?.level, .warning)
    }

    func testParseTemplateError() {
        // Template errors in Hugo are prefixed with ERROR
        let line = "ERROR 2024/01/15 10:30:00 template: shortcodes/gallery.html:10: function \"undefined\" not defined"

        let error = BuildErrorParser.parseLine(line)

        XCTAssertNotNil(error)
        XCTAssertEqual(error?.file, "shortcodes/gallery.html")
        XCTAssertEqual(error?.line, 10)
    }

    func testExtractFileLocationWithLineNumber() {
        let text = "Error in layouts/partials/header.html:42:13: unexpected end of input"

        let (file, line) = BuildErrorParser.extractFileLocation(from: text)

        XCTAssertEqual(file, "layouts/partials/header.html")
        XCTAssertEqual(line, 42)
    }

    func testExtractFileLocationFromTemplateLine() {
        let text = "template: _default/single.html:15: unexpected EOF"

        let (file, line) = BuildErrorParser.extractFileLocation(from: text)

        XCTAssertEqual(file, "_default/single.html")
        XCTAssertEqual(line, 15)
    }

    func testCleanMessageRemovesTimestamp() {
        let message = "ERROR 2024/01/15 10:30:00 Error building site: parse failed"

        let cleaned = BuildErrorParser.cleanMessage(message)

        XCTAssertEqual(cleaned, "Error building site: parse failed")
    }

    func testParseServerReady() {
        let line = "Web Server is available at http://localhost:1313/ (bind address 127.0.0.1)"

        let port = BuildErrorParser.parseServerReady(line)

        XCTAssertEqual(port, 1313)
    }

    func testParseServerReadyCustomPort() {
        let line = "Web Server is available at http://localhost:3000/"

        let port = BuildErrorParser.parseServerReady(line)

        XCTAssertEqual(port, 3000)
    }

    func testParseServerReadyReturnsNilForOtherLines() {
        let line = "Building sites..."

        let port = BuildErrorParser.parseServerReady(line)

        XCTAssertNil(port)
    }

    func testIsRebuildingLine() {
        XCTAssertTrue(BuildErrorParser.isRebuildingLine("Change detected, rebuilding site."))
        XCTAssertTrue(BuildErrorParser.isRebuildingLine("Rebuilding site..."))
        XCTAssertFalse(BuildErrorParser.isRebuildingLine("Building sites..."))
    }

    func testParseBuildComplete() {
        let line = "Total in 123 ms"

        let time = BuildErrorParser.parseBuildComplete(line)

        XCTAssertEqual(time, 123)
    }

    func testParseBuildCompleteReturnsNilForOtherLines() {
        let line = "Built 42 pages in 3.2s"

        let time = BuildErrorParser.parseBuildComplete(line)

        XCTAssertNil(time)
    }

    func testParseMultipleLines() {
        let output = """
        Building sites...
        ERROR 2024/01/15 10:30:00 Error building site: parse failed
        WARN 2024/01/15 10:30:01 Missing layout file
        Total in 50 ms
        """

        let errors = BuildErrorParser.parseOutput(output)

        XCTAssertEqual(errors.count, 2)
        XCTAssertEqual(errors[0].level, .error)
        XCTAssertEqual(errors[1].level, .warning)
    }

    func testNormalLineReturnsNil() {
        let line = "Built 10 pages and processed 5 images"

        let error = BuildErrorParser.parseLine(line)

        XCTAssertNil(error)
    }

    // MARK: - HugoServerStatus Tests

    func testHugoServerStatusDisplayText() {
        XCTAssertEqual(HugoServerStatus.stopped.displayText, "Stopped")
        XCTAssertEqual(HugoServerStatus.starting.displayText, "Starting...")
        XCTAssertEqual(HugoServerStatus.running(port: 1313).displayText, "Running on port 1313")
        XCTAssertEqual(HugoServerStatus.error(message: "Test error").displayText, "Error: Test error")
    }

    func testHugoServerStatusIsRunning() {
        XCTAssertFalse(HugoServerStatus.stopped.isRunning)
        XCTAssertFalse(HugoServerStatus.starting.isRunning)
        XCTAssertTrue(HugoServerStatus.running(port: 1313).isRunning)
        XCTAssertFalse(HugoServerStatus.error(message: "Test").isRunning)
    }

    // MARK: - HugoServerConfig Tests

    func testDefaultConfig() {
        let config = HugoServerConfig()

        XCTAssertEqual(config.port, 1313)
        XCTAssertEqual(config.bindAddress, "localhost")
        XCTAssertTrue(config.buildDrafts)
        XCTAssertTrue(config.buildFuture)
        XCTAssertFalse(config.buildExpired)
        XCTAssertTrue(config.watch)
        XCTAssertTrue(config.navigateToChanged)
        XCTAssertFalse(config.disableLiveReload)
    }

    // MARK: - HugoBuildError Tests

    func testBuildErrorClickableFilePath() {
        let errorWithLine = HugoBuildError(
            level: .error,
            message: "Test error",
            file: "layouts/index.html",
            line: 42,
            timestamp: Date()
        )

        XCTAssertEqual(errorWithLine.clickableFilePath, "layouts/index.html:42")

        let errorWithoutLine = HugoBuildError(
            level: .error,
            message: "Test error",
            file: "layouts/index.html",
            line: nil,
            timestamp: Date()
        )

        XCTAssertEqual(errorWithoutLine.clickableFilePath, "layouts/index.html")

        let errorWithoutFile = HugoBuildError(
            level: .error,
            message: "Test error",
            file: nil,
            line: nil,
            timestamp: Date()
        )

        XCTAssertNil(errorWithoutFile.clickableFilePath)
    }

    // MARK: - HugoServerError Tests

    func testHugoServerErrorDescriptions() {
        XCTAssertEqual(
            HugoServerError.hugoNotFound.errorDescription,
            "Hugo is not installed or not found in PATH. Please install Hugo first."
        )

        XCTAssertEqual(
            HugoServerError.portInUse(1313).errorDescription,
            "Port 1313 is already in use. Please choose a different port."
        )

        XCTAssertEqual(
            HugoServerError.startFailed("test reason").errorDescription,
            "Failed to start Hugo server: test reason"
        )

        XCTAssertEqual(
            HugoServerError.notRunning.errorDescription,
            "Hugo server is not running"
        )
    }

    // MARK: - AsyncStream Observation Tests (WP3.5 Cluster 9 / M2)
    //
    // These exercise `HugoServerService`'s stream factories directly, without
    // starting a real Hugo subprocess (CI has no guarantee Hugo is installed,
    // and the manual test checklist in Docs/SC6-BURNDOWN-MEMO.md §5 covers
    // the full start/stop/crash lifecycle against a live server). What's
    // covered here is the part that's new behavior and fully unit-testable in
    // isolation: replay-on-subscribe, and that each subscriber gets an
    // independent stream rather than splitting elements between consumers.

    /// A freshly-created status stream must immediately replay the current
    /// status as its first element - a late subscriber (e.g. the Server Logs
    /// window opened after the server already started) shouldn't have to
    /// separately fetch `status` first. This is new behavior, not a port of
    /// something that existed before the AsyncStream conversion.
    func testStatusUpdatesReplaysCurrentStatusOnSubscribe() async throws {
        let stream = await HugoServerService.shared.statusUpdates()
        var iterator = stream.makeAsyncIterator()

        let firstElement = await iterator.next()
        XCTAssertNotNil(firstElement, "statusUpdates() must yield at least one element (the replayed current status) immediately on subscribe")
    }

    /// Same replay-on-subscribe guarantee for buildErrorUpdates().
    func testBuildErrorUpdatesReplaysCurrentErrorsOnSubscribe() async throws {
        let stream = await HugoServerService.shared.buildErrorUpdates()
        var iterator = stream.makeAsyncIterator()

        let firstElement = await iterator.next()
        XCTAssertNotNil(firstElement, "buildErrorUpdates() must yield at least one element (the replayed current errors) immediately on subscribe")
    }

    /// Same replay-on-subscribe guarantee for outputUpdates().
    func testOutputUpdatesReplaysCurrentOutputOnSubscribe() async throws {
        let stream = await HugoServerService.shared.outputUpdates()
        var iterator = stream.makeAsyncIterator()

        let firstElement = await iterator.next()
        XCTAssertNotNil(firstElement, "outputUpdates() must yield at least one element (the replayed current output) immediately on subscribe")
    }

    /// `AsyncStream` is single-consumer: two `for await` loops over the *same*
    /// stream split elements between them rather than both seeing every
    /// element. The whole point of the stream-factory design (WP3.5 Cluster 9)
    /// is that each call to `statusUpdates()` returns an *independent*
    /// stream+continuation pair, so two independent subscribers (e.g.
    /// SiteViewModel and ServerControlView, both observing at once) each get
    /// their own replayed value rather than racing over one shared stream.
    func testMultipleStatusSubscribersEachReplayIndependently() async throws {
        let streamA = await HugoServerService.shared.statusUpdates()
        let streamB = await HugoServerService.shared.statusUpdates()

        var iteratorA = streamA.makeAsyncIterator()
        var iteratorB = streamB.makeAsyncIterator()

        let firstA = await iteratorA.next()
        let firstB = await iteratorB.next()

        XCTAssertNotNil(firstA, "First subscriber must receive the replayed current status")
        XCTAssertNotNil(firstB, "Second, independent subscriber must ALSO receive the replayed current status - not have it consumed by the first subscriber")
    }

    /// Cancelling the consuming `Task` is the only deregistration mechanism
    /// now (no more `removeOnXChange(id:)`) - confirm that cancellation
    /// actually ends the `for await` loop rather than hanging forever.
    func testStatusUpdatesStreamEndsWhenConsumingTaskIsCancelled() async throws {
        let receivedFirstElement = XCTestExpectation(description: "received at least one element")
        let loopEnded = XCTestExpectation(description: "for-await loop ended after cancellation")

        let task = Task {
            let stream = await HugoServerService.shared.statusUpdates()
            for await _ in stream {
                receivedFirstElement.fulfill()
            }
            loopEnded.fulfill()
        }

        await fulfillment(of: [receivedFirstElement], timeout: 2.0)
        task.cancel()
        await fulfillment(of: [loopEnded], timeout: 2.0)
    }
}
