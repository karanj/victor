import XCTest
import SwiftUI
@testable import Victor

/// Tests for AppSettings: default values, UserDefaults round-tripping, and
/// agreement between the MainActor-isolated instance properties and the
/// `nonisolated static` accessors non-MainActor callers use.
///
/// Uses `AppSettings.makeForTesting()` (DEBUG-only factory) rather than
/// `AppSettings.shared` so each test gets an isolated instance instead of
/// mutating the process-wide singleton other tests may already have touched.
@MainActor
final class AppSettingsTests: XCTestCase {

    /// Every UserDefaults key AppSettings owns, for setUp/tearDown cleanup.
    private let allKeys: [String] = [
        AppConstants.UserDefaultsKeys.highlightCurrentLine,
        AppConstants.UserDefaultsKeys.editorFontSize,
        AppConstants.UserDefaultsKeys.editorFontName,
        AppConstants.UserDefaultsKeys.editorLayoutMode,
        AppConstants.UserDefaultsKeys.isInspectorVisible,
        AppConstants.UserDefaultsKeys.frontmatterPanelHeight,
        AppConstants.UserDefaultsKeys.isAutoSaveEnabled,
        AppConstants.UserDefaultsKeys.autoSaveDelay,
        AppConstants.UserDefaultsKeys.badgeColorDraft,
        AppConstants.UserDefaultsKeys.badgeColorScheduled,
        AppConstants.UserDefaultsKeys.badgeColorExpired,
        AppConstants.UserDefaultsKeys.hugoServerPort,
        AppConstants.UserDefaultsKeys.hugoServerBuildDrafts,
        AppConstants.UserDefaultsKeys.hugoServerBuildFuture,
        AppConstants.UserDefaultsKeys.hugoServerBuildExpired
    ]

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        for key in allKeys {
            defaults.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        for key in allKeys {
            defaults.removeObject(forKey: key)
        }
        super.tearDown()
    }

    // MARK: - Defaults (key absent)

    func testDefaultsWhenKeysAreAbsent() {
        let settings = AppSettings.makeForTesting()

        XCTAssertTrue(settings.isAutoSaveEnabled, "isAutoSaveEnabled should default to AppConstants.AutoSave.defaultEnabled")
        XCTAssertEqual(settings.autoSaveDelay, AppConstants.AutoSave.debounceInterval)
        XCTAssertTrue(settings.highlightCurrentLine)
        XCTAssertEqual(settings.editorFontSize, 13.0)
        XCTAssertEqual(settings.editorFontName, "SF Mono")
        XCTAssertEqual(settings.layoutMode, .split)
        XCTAssertFalse(settings.isInspectorVisible)
        XCTAssertEqual(settings.badgeColorDraftHex, Color.BadgeColorKey.draft.defaultHex)
        XCTAssertEqual(settings.badgeColorScheduledHex, Color.BadgeColorKey.scheduled.defaultHex)
        XCTAssertEqual(settings.badgeColorExpiredHex, Color.BadgeColorKey.expired.defaultHex)
        XCTAssertEqual(settings.hugoServerPort, 1313)
        XCTAssertTrue(settings.hugoServerBuildDrafts)
        XCTAssertTrue(settings.hugoServerBuildFuture)
        XCTAssertFalse(settings.hugoServerBuildExpired)
        XCTAssertEqual(settings.frontmatterPanelHeight, 300.0)
    }

    // MARK: - Round-trip: set -> UserDefaults -> fresh read

    func testRoundTripIsAutoSaveEnabled() {
        let settings = AppSettings.makeForTesting()
        settings.isAutoSaveEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.isAutoSaveEnabled))
        XCTAssertFalse(AppSettings.makeForTesting().isAutoSaveEnabled)
    }

    func testRoundTripAutoSaveDelay() {
        let settings = AppSettings.makeForTesting()
        settings.autoSaveDelay = 5.0
        XCTAssertEqual(UserDefaults.standard.double(forKey: AppConstants.UserDefaultsKeys.autoSaveDelay), 5.0)
        XCTAssertEqual(AppSettings.makeForTesting().autoSaveDelay, 5.0)
    }

    func testRoundTripHighlightCurrentLine() {
        let settings = AppSettings.makeForTesting()
        settings.highlightCurrentLine = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.highlightCurrentLine))
        XCTAssertFalse(AppSettings.makeForTesting().highlightCurrentLine)
    }

    func testRoundTripEditorFontSize() {
        let settings = AppSettings.makeForTesting()
        settings.editorFontSize = 18.0
        XCTAssertEqual(UserDefaults.standard.double(forKey: AppConstants.UserDefaultsKeys.editorFontSize), 18.0)
        XCTAssertEqual(AppSettings.makeForTesting().editorFontSize, 18.0)
    }

    func testRoundTripEditorFontName() {
        let settings = AppSettings.makeForTesting()
        settings.editorFontName = "Menlo"
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.editorFontName), "Menlo")
        XCTAssertEqual(AppSettings.makeForTesting().editorFontName, "Menlo")
    }

    func testRoundTripLayoutMode() {
        let settings = AppSettings.makeForTesting()
        settings.layoutMode = .preview
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.editorLayoutMode), EditorLayoutMode.preview.rawValue)
        XCTAssertEqual(AppSettings.makeForTesting().layoutMode, .preview)
    }

    func testRoundTripIsInspectorVisible() {
        let settings = AppSettings.makeForTesting()
        settings.isInspectorVisible = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.isInspectorVisible))
        XCTAssertTrue(AppSettings.makeForTesting().isInspectorVisible)
    }

    func testRoundTripFrontmatterPanelHeight() {
        let settings = AppSettings.makeForTesting()
        settings.frontmatterPanelHeight = 420.0
        XCTAssertEqual(UserDefaults.standard.double(forKey: AppConstants.UserDefaultsKeys.frontmatterPanelHeight), 420.0)
        XCTAssertEqual(AppSettings.makeForTesting().frontmatterPanelHeight, 420.0)
    }

    func testRoundTripBadgeColors() {
        let settings = AppSettings.makeForTesting()
        settings.badgeColorDraftHex = "#123456"
        settings.badgeColorScheduledHex = "#654321"
        settings.badgeColorExpiredHex = "#ABCDEF"

        XCTAssertEqual(UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.badgeColorDraft), "#123456")
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.badgeColorScheduled), "#654321")
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.badgeColorExpired), "#ABCDEF")

        let fresh = AppSettings.makeForTesting()
        XCTAssertEqual(fresh.badgeColorDraftHex, "#123456")
        XCTAssertEqual(fresh.badgeColorScheduledHex, "#654321")
        XCTAssertEqual(fresh.badgeColorExpiredHex, "#ABCDEF")
    }

    func testRoundTripHugoServerSettings() {
        let settings = AppSettings.makeForTesting()
        settings.hugoServerPort = 4000
        settings.hugoServerBuildDrafts = false
        settings.hugoServerBuildFuture = false
        settings.hugoServerBuildExpired = true

        XCTAssertEqual(UserDefaults.standard.integer(forKey: AppConstants.UserDefaultsKeys.hugoServerPort), 4000)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.hugoServerBuildDrafts))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.hugoServerBuildFuture))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.hugoServerBuildExpired))

        let fresh = AppSettings.makeForTesting()
        XCTAssertEqual(fresh.hugoServerPort, 4000)
        XCTAssertFalse(fresh.hugoServerBuildDrafts)
        XCTAssertFalse(fresh.hugoServerBuildFuture)
        XCTAssertTrue(fresh.hugoServerBuildExpired)
    }

    // MARK: - layoutMode invalid rawValue fallback

    func testLayoutModeFallsBackToSplitOnInvalidRawValue() {
        UserDefaults.standard.set("not-a-real-mode", forKey: AppConstants.UserDefaultsKeys.editorLayoutMode)
        let settings = AppSettings.makeForTesting()
        XCTAssertEqual(settings.layoutMode, .split)
    }

    func testLayoutModeFallsBackToSplitOnMissingValue() {
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.editorLayoutMode)
        let settings = AppSettings.makeForTesting()
        XCTAssertEqual(settings.layoutMode, .split)
    }

    // MARK: - Static accessors agree with instance properties

    func testStaticAccessorsAgreeWithInstanceAtDefaults() {
        let settings = AppSettings.makeForTesting()

        XCTAssertEqual(AppSettings.currentIsAutoSaveEnabled(), settings.isAutoSaveEnabled)
        XCTAssertEqual(AppSettings.currentAutoSaveDelay(), settings.autoSaveDelay)
        XCTAssertEqual(AppSettings.currentHugoServerPort(), settings.hugoServerPort)
        XCTAssertEqual(AppSettings.currentHugoServerBuildDrafts(), settings.hugoServerBuildDrafts)
        XCTAssertEqual(AppSettings.currentHugoServerBuildFuture(), settings.hugoServerBuildFuture)
        XCTAssertEqual(AppSettings.currentHugoServerBuildExpired(), settings.hugoServerBuildExpired)
    }

    func testStaticAccessorsAgreeWithInstanceAfterSetting() {
        let settings = AppSettings.makeForTesting()
        settings.isAutoSaveEnabled = false
        settings.autoSaveDelay = 7.5
        settings.hugoServerPort = 9000
        settings.hugoServerBuildDrafts = false
        settings.hugoServerBuildFuture = false
        settings.hugoServerBuildExpired = true

        XCTAssertEqual(AppSettings.currentIsAutoSaveEnabled(), false)
        XCTAssertEqual(AppSettings.currentAutoSaveDelay(), 7.5)
        XCTAssertEqual(AppSettings.currentHugoServerPort(), 9000)
        XCTAssertEqual(AppSettings.currentHugoServerBuildDrafts(), false)
        XCTAssertEqual(AppSettings.currentHugoServerBuildFuture(), false)
        XCTAssertEqual(AppSettings.currentHugoServerBuildExpired(), true)

        // And a fresh instance constructed after the writes agrees too.
        let fresh = AppSettings.makeForTesting()
        XCTAssertEqual(fresh.isAutoSaveEnabled, AppSettings.currentIsAutoSaveEnabled())
        XCTAssertEqual(fresh.autoSaveDelay, AppSettings.currentAutoSaveDelay())
        XCTAssertEqual(fresh.hugoServerPort, AppSettings.currentHugoServerPort())
        XCTAssertEqual(fresh.hugoServerBuildDrafts, AppSettings.currentHugoServerBuildDrafts())
        XCTAssertEqual(fresh.hugoServerBuildFuture, AppSettings.currentHugoServerBuildFuture())
        XCTAssertEqual(fresh.hugoServerBuildExpired, AppSettings.currentHugoServerBuildExpired())
    }
}
