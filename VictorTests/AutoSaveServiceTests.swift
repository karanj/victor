import XCTest
@testable import Victor

/// Tests for AutoSaveService debouncing, per-file scheduling, and delay preference.
///
/// victor-zw4: each test constructs its own `AutoSaveService()` instance instead of
/// reaching `AutoSaveService.shared` - the actor's `init()` is now non-private for
/// exactly this reason. A fresh instance per test means pending-save state (saveTasks/
/// saveTokens) from one test can never bleed into another via the process-wide
/// singleton, which is what made this suite need serialized UserDefaults cleanup
/// before. The debounce interval itself is still read from `AppSettings`/UserDefaults
/// statics (`AppSettings.currentAutoSaveDelay()`), so that setup/teardown is unchanged.
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

        let service = AutoSaveService()
        let fileA = try makeFile(named: "a.md", content: "original A")
        let fileB = try makeFile(named: "b.md", content: "original B")
        let pastDate = Date.distantPast

        await service.scheduleAutoSave(
            fileURL: fileA,
            content: "edited A",
            lastModified: pastDate,
            onConflict: { .keepLocal },
            onSuccess: { _ in },
            onError: { _ in }
        )

        // Schedule B while A's debounce is still pending
        await service.scheduleAutoSave(
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

        let service = AutoSaveService()
        let file = try makeFile(named: "slow.md", content: "original")

        await service.scheduleAutoSave(
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

        await service.cancelAutoSave()
    }

    /// victor-zw4 isolation proof: two independently-constructed `AutoSaveService`
    /// instances must not share pending-save state. Scheduling (and cancelling) a
    /// save on instance A must have no effect on instance B's pending save for the
    /// same file URL - if the two accidentally shared state (e.g. both still resolved
    /// to the same `.shared` singleton), cancelling on A would also cancel B's save,
    /// and B's file would never be written.
    func testTwoInstancesHaveIndependentPendingSaves() async throws {
        UserDefaults.standard.set(0.3, forKey: AppConstants.UserDefaultsKeys.autoSaveDelay)

        let serviceA = AutoSaveService()
        let serviceB = AutoSaveService()
        let file = try makeFile(named: "shared-name.md", content: "original")

        await serviceA.scheduleAutoSave(
            fileURL: file,
            content: "from A",
            lastModified: .distantPast,
            onConflict: { .keepLocal },
            onSuccess: { _ in },
            onError: { _ in }
        )
        await serviceB.scheduleAutoSave(
            fileURL: file,
            content: "from B",
            lastModified: .distantPast,
            onConflict: { .keepLocal },
            onSuccess: { _ in },
            onError: { _ in }
        )

        // Cancelling on A must not touch B's independently-scheduled save
        await serviceA.cancelAutoSave(for: file)

        try await Task.sleep(for: .seconds(1.0))

        let onDisk = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(
            onDisk, "from B",
            "Instance B's pending save must complete independently of instance A's cancellation - " +
            "the two AutoSaveService instances must not share saveTasks/saveTokens state"
        )
    }
}
