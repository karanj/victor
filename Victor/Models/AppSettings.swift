import Foundation
import SwiftUI

/// Centralized, UserDefaults-backed application settings.
///
/// One explicit property per preference; each property's key and default are
/// defined exactly once here. `didSet` persists immediately to UserDefaults.
/// Views bind to `AppSettings.shared` via `@Bindable` instead of `@AppStorage`,
/// so the File-menu toggle and the Preferences window observe the same state
/// (see Docs/MAC-POLISH-DESIGN.md W0).
///
/// Non-MainActor readers (e.g. `AutoSaveService`, an `actor`) cannot touch this
/// MainActor-isolated instance, so a handful of `nonisolated static` accessors
/// below read the same key/default pair directly from UserDefaults. Both access
/// patterns route through the same private `read*` helper, so they cannot disagree.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    // MARK: - Editor

    /// Highlight the current line in the markdown/text editor.
    var highlightCurrentLine: Bool {
        didSet {
            UserDefaults.standard.set(highlightCurrentLine, forKey: AppConstants.UserDefaultsKeys.highlightCurrentLine)
        }
    }

    /// Editor font size in points.
    var editorFontSize: Double {
        didSet {
            UserDefaults.standard.set(editorFontSize, forKey: AppConstants.UserDefaultsKeys.editorFontSize)
        }
    }

    /// Editor font family name.
    var editorFontName: String {
        didSet {
            UserDefaults.standard.set(editorFontName, forKey: AppConstants.UserDefaultsKeys.editorFontName)
        }
    }

    /// Editor layout mode: editor only, preview only, or split. Stored as its
    /// rawValue; falls back to `.split` if the stored value is missing or invalid.
    var layoutMode: EditorLayoutMode {
        didSet {
            UserDefaults.standard.set(layoutMode.rawValue, forKey: AppConstants.UserDefaultsKeys.editorLayoutMode)
        }
    }

    /// Inspector panel visibility.
    var isInspectorVisible: Bool {
        didSet {
            UserDefaults.standard.set(isInspectorVisible, forKey: AppConstants.UserDefaultsKeys.isInspectorVisible)
        }
    }

    /// Height of the frontmatter bottom panel.
    var frontmatterPanelHeight: Double {
        didSet {
            UserDefaults.standard.set(frontmatterPanelHeight, forKey: AppConstants.UserDefaultsKeys.frontmatterPanelHeight)
        }
    }

    // MARK: - Auto-Save

    /// Whether auto-save is enabled.
    var isAutoSaveEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoSaveEnabled, forKey: AppConstants.UserDefaultsKeys.isAutoSaveEnabled)
        }
    }

    /// Auto-save debounce delay, in seconds.
    var autoSaveDelay: Double {
        didSet {
            UserDefaults.standard.set(autoSaveDelay, forKey: AppConstants.UserDefaultsKeys.autoSaveDelay)
        }
    }

    // MARK: - Badge Colors

    /// Draft content badge color, stored as a hex string.
    var badgeColorDraftHex: String {
        didSet {
            UserDefaults.standard.set(badgeColorDraftHex, forKey: AppConstants.UserDefaultsKeys.badgeColorDraft)
        }
    }

    /// Scheduled content badge color, stored as a hex string.
    var badgeColorScheduledHex: String {
        didSet {
            UserDefaults.standard.set(badgeColorScheduledHex, forKey: AppConstants.UserDefaultsKeys.badgeColorScheduled)
        }
    }

    /// Expired content badge color, stored as a hex string.
    var badgeColorExpiredHex: String {
        didSet {
            UserDefaults.standard.set(badgeColorExpiredHex, forKey: AppConstants.UserDefaultsKeys.badgeColorExpired)
        }
    }

    // MARK: - Hugo Server Defaults

    /// Default port for the Hugo development server.
    var hugoServerPort: Int {
        didSet {
            UserDefaults.standard.set(hugoServerPort, forKey: AppConstants.UserDefaultsKeys.hugoServerPort)
        }
    }

    /// Whether the Hugo server builds draft content by default.
    var hugoServerBuildDrafts: Bool {
        didSet {
            UserDefaults.standard.set(hugoServerBuildDrafts, forKey: AppConstants.UserDefaultsKeys.hugoServerBuildDrafts)
        }
    }

    /// Whether the Hugo server builds future-dated content by default.
    var hugoServerBuildFuture: Bool {
        didSet {
            UserDefaults.standard.set(hugoServerBuildFuture, forKey: AppConstants.UserDefaultsKeys.hugoServerBuildFuture)
        }
    }

    /// Whether the Hugo server builds expired content by default.
    var hugoServerBuildExpired: Bool {
        didSet {
            UserDefaults.standard.set(hugoServerBuildExpired, forKey: AppConstants.UserDefaultsKeys.hugoServerBuildExpired)
        }
    }

    /// Whether to post a system notification when a Hugo build fails while
    /// Victor isn't the active app (Docs/MAC-POLISH-DESIGN.md W3.4). In-app
    /// failures always show in `BuildErrorOverlay` regardless of this setting.
    var notifyOnBuildFailure: Bool {
        didSet {
            UserDefaults.standard.set(notifyOnBuildFailure, forKey: AppConstants.UserDefaultsKeys.notifyOnBuildFailure)
        }
    }

    // MARK: - Initialization

    private init() {
        let defaults = UserDefaults.standard

        highlightCurrentLine = defaults.object(forKey: AppConstants.UserDefaultsKeys.highlightCurrentLine) as? Bool ?? true
        editorFontSize = defaults.object(forKey: AppConstants.UserDefaultsKeys.editorFontSize) as? Double ?? 13.0
        editorFontName = defaults.string(forKey: AppConstants.UserDefaultsKeys.editorFontName) ?? "SF Mono"

        if let savedMode = defaults.string(forKey: AppConstants.UserDefaultsKeys.editorLayoutMode),
           let mode = EditorLayoutMode(rawValue: savedMode) {
            layoutMode = mode
        } else {
            layoutMode = .split
        }

        isInspectorVisible = defaults.object(forKey: AppConstants.UserDefaultsKeys.isInspectorVisible) as? Bool ?? false
        frontmatterPanelHeight = defaults.object(forKey: AppConstants.UserDefaultsKeys.frontmatterPanelHeight) as? Double ?? 300.0

        isAutoSaveEnabled = Self.readIsAutoSaveEnabled(from: defaults)
        autoSaveDelay = Self.readAutoSaveDelay(from: defaults)

        badgeColorDraftHex = defaults.string(forKey: AppConstants.UserDefaultsKeys.badgeColorDraft) ?? Color.BadgeColorKey.draft.defaultHex
        badgeColorScheduledHex = defaults.string(forKey: AppConstants.UserDefaultsKeys.badgeColorScheduled) ?? Color.BadgeColorKey.scheduled.defaultHex
        badgeColorExpiredHex = defaults.string(forKey: AppConstants.UserDefaultsKeys.badgeColorExpired) ?? Color.BadgeColorKey.expired.defaultHex

        hugoServerPort = Self.readHugoServerPort(from: defaults)
        hugoServerBuildDrafts = Self.readHugoServerBuildDrafts(from: defaults)
        hugoServerBuildFuture = Self.readHugoServerBuildFuture(from: defaults)
        hugoServerBuildExpired = Self.readHugoServerBuildExpired(from: defaults)
        notifyOnBuildFailure = Self.readNotifyOnBuildFailure(from: defaults)
    }

    #if DEBUG
    /// Test-only: construct an isolated instance instead of touching the
    /// process-wide `.shared` singleton. `AppSettings` intentionally has no
    /// public initializer (every call site should share one instance); this
    /// factory exists solely so tests can verify default-loading and
    /// round-trip behavior without cross-test pollution of `.shared`.
    static func makeForTesting() -> AppSettings {
        AppSettings()
    }
    #endif

    // MARK: - Nonisolated Static Accessors

    // Non-MainActor callers (AutoSaveService, an actor) can't reach the instance
    // above, so they read the same UserDefaults key/default pair through these.
    // Both this and the matching instance property route through the same
    // private `read*` helper, so the two access patterns cannot diverge.

    nonisolated static func currentIsAutoSaveEnabled() -> Bool {
        readIsAutoSaveEnabled(from: .standard)
    }

    nonisolated static func currentAutoSaveDelay() -> Double {
        readAutoSaveDelay(from: .standard)
    }

    nonisolated static func currentHugoServerPort() -> Int {
        readHugoServerPort(from: .standard)
    }

    nonisolated static func currentHugoServerBuildDrafts() -> Bool {
        readHugoServerBuildDrafts(from: .standard)
    }

    nonisolated static func currentHugoServerBuildFuture() -> Bool {
        readHugoServerBuildFuture(from: .standard)
    }

    nonisolated static func currentHugoServerBuildExpired() -> Bool {
        readHugoServerBuildExpired(from: .standard)
    }

    /// Read by `HugoServerService` (an actor) at the empty -> non-empty
    /// build-error transition, before deciding whether to post a
    /// notification.
    nonisolated static func currentNotifyOnBuildFailure() -> Bool {
        readNotifyOnBuildFailure(from: .standard)
    }

    // MARK: - Shared Key/Default Definitions

    private nonisolated static func readIsAutoSaveEnabled(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: AppConstants.UserDefaultsKeys.isAutoSaveEnabled) as? Bool ?? AppConstants.AutoSave.defaultEnabled
    }

    private nonisolated static func readAutoSaveDelay(from defaults: UserDefaults) -> Double {
        defaults.object(forKey: AppConstants.UserDefaultsKeys.autoSaveDelay) as? Double ?? AppConstants.AutoSave.debounceInterval
    }

    private nonisolated static func readHugoServerPort(from defaults: UserDefaults) -> Int {
        defaults.object(forKey: AppConstants.UserDefaultsKeys.hugoServerPort) as? Int ?? 1313
    }

    private nonisolated static func readHugoServerBuildDrafts(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: AppConstants.UserDefaultsKeys.hugoServerBuildDrafts) as? Bool ?? true
    }

    private nonisolated static func readHugoServerBuildFuture(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: AppConstants.UserDefaultsKeys.hugoServerBuildFuture) as? Bool ?? true
    }

    private nonisolated static func readHugoServerBuildExpired(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: AppConstants.UserDefaultsKeys.hugoServerBuildExpired) as? Bool ?? false
    }

    private nonisolated static func readNotifyOnBuildFailure(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: AppConstants.UserDefaultsKeys.notifyOnBuildFailure) as? Bool ?? true
    }
}
