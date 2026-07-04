import XCTest
@testable import Victor

/// Tests for `withFileCoordination`, the shared helper that replaced the hand-rolled
/// `withCheckedThrowingContinuation` + `didResume` dance previously duplicated in
/// `AutoSaveService.performSave`, `FileSystemService.renameFile`, and
/// `FileSystemService.duplicateFile` (victor-mod grab-bag item 3).
///
/// Covers the three paths the helper's contract distinguishes: the accessor block
/// succeeding, the accessor block failing (including a thrown error), and coordination
/// itself failing before the accessor block ever runs.
final class FileCoordinationHelperTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileCoordinationHelperTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - Success path

    /// The accessor block runs, writes the file, and resumes with `.success` -
    /// exercised against a real `NSFileCoordinator` write to a temp file.
    func testSuccessPathWritesFileAndReturnsValue() async throws {
        let url = tempDirectory.appendingPathComponent("success.md")
        let content = "# Hello"

        let returnedURL: URL = try await withFileCoordination { resume in
            let coordinator = NSFileCoordinator()
            var coordinatorError: NSError?
            coordinator.coordinate(writingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
                do {
                    try content.write(to: coordinatedURL, atomically: true, encoding: .utf8)
                    resume(.success(coordinatedURL))
                } catch {
                    resume(.failure(error))
                }
            }
            return coordinatorError
        }

        XCTAssertEqual(returnedURL, url)
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(onDisk, content)
    }

    // MARK: - Thrown-in-block path

    /// The accessor block runs but the operation inside it throws (writing to a
    /// directory that doesn't exist) - the thrown error must propagate as-is, not be
    /// swallowed or replaced by a spurious `coordinatorError` resume.
    func testThrownInBlockPropagatesTheOriginalError() async {
        let url = tempDirectory
            .appendingPathComponent("no-such-subdirectory")
            .appendingPathComponent("file.md")

        do {
            let _: URL = try await withFileCoordination { resume in
                let coordinator = NSFileCoordinator()
                var coordinatorError: NSError?
                coordinator.coordinate(writingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
                    do {
                        try "content".write(to: coordinatedURL, atomically: true, encoding: .utf8)
                        resume(.success(coordinatedURL))
                    } catch {
                        resume(.failure(error))
                    }
                }
                return coordinatorError
            }
            XCTFail("Expected the write to throw for a missing intermediate directory")
        } catch {
            // The specific error is `NSCocoaErrorDomain` "no such file" - just confirm
            // an error propagated and the file was never created.
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    // MARK: - Coordinator-error path

    /// When coordination itself fails *before* the accessor block ever runs,
    /// `NSFileCoordinator.coordinate` sets its `error:` out-parameter and never invokes
    /// the accessor at all - so `resume` is never called from inside the block. This is
    /// difficult to trigger deterministically with a genuine `NSFileCoordinator` in a
    /// unit test (it requires an actual competing file presenter/coordinator), so this
    /// exercises the helper's own contract directly: a `body` that returns a non-nil
    /// `NSError` without ever calling `resume` must still resolve the `async` call by
    /// throwing that error.
    func testCoordinatorErrorPathThrowsWhenAccessorBlockNeverRuns() async {
        let simulatedError = NSError(domain: "FileCoordinationHelperTests", code: 42)

        do {
            let _: Int = try await withFileCoordination { _ in
                // Simulates `coordinate(...)` failing up front: the accessor block
                // (and therefore `resume`) never runs.
                simulatedError
            }
            XCTFail("Expected the simulated coordinator error to propagate")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, simulatedError.domain)
            XCTAssertEqual(error.code, simulatedError.code)
        }
    }

    // MARK: - Double-resume guard

    /// If a caller's accessor block somehow calls `resume` more than once (shouldn't
    /// happen in the real call sites, but the helper's `didResume` guard exists
    /// specifically to make it harmless), only the first call wins.
    func testOnlyFirstResumeCallWins() async throws {
        let value: Int = try await withFileCoordination { resume in
            resume(.success(1))
            resume(.success(2))
            resume(.failure(NSError(domain: "should-be-ignored", code: 1)))
            return nil
        }
        XCTAssertEqual(value, 1)
    }
}
