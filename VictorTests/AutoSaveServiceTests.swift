import XCTest
@testable import Victor

/// Tests for AutoSaveService debouncing, per-file scheduling, and delay preference
final class AutoSaveServiceTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoSaveServiceTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.autoSaveDelay)
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeFile(named name: String, content: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Scheduling a save for file B must not cancel the pending save for file A.
    /// A single global debounce task silently drops file A's edits.
    func testSchedulingSecondFileDoesNotCancelFirstFilesPendingSave() async throws {
        UserDefaults.standard.set(0.2, forKey: AppConstants.UserDefaultsKeys.autoSaveDelay)

        let fileA = try makeFile(named: "a.md", content: "original A")
        let fileB = try makeFile(named: "b.md", content: "original B")
        let pastDate = Date.distantPast

        await AutoSaveService.shared.scheduleAutoSave(
            fileURL: fileA,
            content: "edited A",
            lastModified: pastDate,
            onConflict: { .keepLocal },
            onSuccess: { _ in },
            onError: { _ in }
        )

        // Schedule B while A's debounce is still pending
        await AutoSaveService.shared.scheduleAutoSave(
            fileURL: fileB,
            content: "edited B",
            lastModified: pastDate,
            onConflict: { .keepLocal },
            onSuccess: { _ in },
            onError: { _ in }
        )

        // Wait past the debounce interval for both saves to land
        try await Task.sleep(for: .seconds(1.5))

        let savedA = try String(contentsOf: fileA, encoding: .utf8)
        let savedB = try String(contentsOf: fileB, encoding: .utf8)
        XCTAssertEqual(savedA, "edited A", "File A's pending save must survive file B being scheduled")
        XCTAssertEqual(savedB, "edited B")
    }

    /// The user-facing "Save after:" preference must control the debounce interval.
    func testAutoSaveHonorsDelayPreference() async throws {
        // With a long configured delay, nothing should be written within a few seconds
        UserDefaults.standard.set(30.0, forKey: AppConstants.UserDefaultsKeys.autoSaveDelay)

        let file = try makeFile(named: "slow.md", content: "original")

        await AutoSaveService.shared.scheduleAutoSave(
            fileURL: file,
            content: "edited",
            lastModified: .distantPast,
            onConflict: { .keepLocal },
            onSuccess: { _ in },
            onError: { _ in }
        )

        // Longer than the legacy hard-coded 2s debounce, far shorter than the 30s preference
        try await Task.sleep(for: .seconds(3))

        let onDisk = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(onDisk, "original", "Save fired before the configured autoSaveDelay elapsed")

        await AutoSaveService.shared.cancelAutoSave()
    }
}
