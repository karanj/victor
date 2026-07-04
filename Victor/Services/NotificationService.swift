import AppKit
import UserNotifications

/// Posts a system notification when a Hugo build fails while Victor is not
/// the active app (Docs/MAC-POLISH-DESIGN.md W3.4). In-app failures are
/// already surfaced by `BuildErrorOverlay`/`BuildIssuesPopover` and never
/// route through here - see `HugoServerService`'s `NSApp.isActive` gate.
///
/// ## Shape: `class + @MainActor`, not `actor`
///
/// CLAUDE.md's service-concurrency table defaults "mutable state accessed
/// from multiple call sites" to `actor`. This service does hold mutable
/// state (`hasRequestedAuthorization`), which would normally point there -
/// but `UNUserNotificationCenterDelegate` conforms to `NSObjectProtocol`,
/// and no Swift `actor` can satisfy that (actors can't subclass `NSObject`
/// or otherwise provide `NSObjectProtocol`'s conformance machinery). The
/// delegate requirement forces a class.
///
/// Given that, this follows the `FileSystemService` row instead
/// ("class + `@MainActor` methods... needs to update UI-bound data"):
/// `NotificationService` posts a notification and, on click, calls
/// `NSApp.activate`, which is itself `@MainActor`-isolated. The two
/// `UNUserNotificationCenterDelegate` methods are marked `nonisolated`
/// because the system invokes them off the main thread; each hops to
/// `@MainActor` only for the one line that needs it, mirroring how
/// `HugoServerService`'s actor-to-`@MainActor` callbacks hop in the
/// opposite direction.
@MainActor
final class NotificationService: NSObject {
    static let shared = NotificationService()

    /// Fixed identifier for build-failure notifications. Reusing it means a
    /// new failure replaces any still-pending/delivered notification from an
    /// earlier burst instead of stacking - there is only ever one live
    /// notification representing "there is currently a failing build".
    private static let buildFailureIdentifier = "com.victor.hugoBuildFailure"

    /// Set once we've asked (granted or denied) so a user who's already been
    /// prompted isn't re-prompted on every subsequent background failure.
    /// Read/written only from `@MainActor` methods on this class.
    private var hasRequestedAuthorization = false

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Request provisional authorization. Provisional delivery means the
    /// notification lands quietly in Notification Center without an upfront
    /// system permission prompt, so this is safe to call on the very first
    /// background build failure rather than at app launch (design risk 4 in
    /// MAC-POLISH-DESIGN.md: prompting at launch, before the user has any
    /// reason to want build alerts, just trains them to deny).
    func requestAuthorizationIfNeeded() async {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }

        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .provisional])
        } catch {
            Logger.shared.warning("[NotificationService] Authorization request failed: \(error.localizedDescription)")
        }
    }

    /// Post (or replace) the build-failure notification. Coalescing to one
    /// notification per build-failure burst is the caller's responsibility -
    /// `HugoServerService` only invokes this on the empty -> non-empty
    /// transition of its error list, not once per parsed error line. The
    /// fixed identifier above is a second line of defense if this is ever
    /// invoked twice for the same burst.
    func postBuildFailure(errorCount: Int, firstMessage: String) async {
        let content = UNMutableNotificationContent()
        content.title = errorCount == 1 ? "Hugo Build Failed" : "Hugo Build Failed (\(errorCount) errors)"
        content.body = firstMessage
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.buildFailureIdentifier,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Logger.shared.warning("[NotificationService] Failed to post build-failure notification: \(error.localizedDescription)")
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    /// Victor never posts while active (see `HugoServerService`'s
    /// `NSApp.isActive` gate), but if a notification is still in flight
    /// right as the app regains focus, present it normally rather than
    /// silently dropping it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// User clicked the notification (or its default action) - bring Victor
    /// to the front.
    ///
    /// Deep-linking straight into the Build Issues popover was considered:
    /// `ServerControlView.isErrorsPopoverPresented` is the only presentation
    /// flag that exists, and it's private `@State` local to that view - not
    /// reachable from a Service without adding a shared observable flag
    /// (e.g. on `SiteViewModel`) and threading it through. That's new
    /// cross-view plumbing beyond this ticket's scope, so this activates the
    /// app only; a follow-up ticket could add
    /// `SiteViewModel.isBuildIssuesPopoverPresented` and have
    /// `ServerControlView` bind its popover to it instead of local `@State`.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
