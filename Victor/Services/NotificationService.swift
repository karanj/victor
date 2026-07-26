import AppKit
import UserNotifications

/// Posts a system notification when a Hugo build fails while Victor is inactive. In-app
/// failures go through `BuildErrorOverlay` instead - see `HugoServerService`'s
/// `NSApp.isActive` gate.
///
/// `class + @MainActor` rather than `actor` despite holding mutable state:
/// `UNUserNotificationCenterDelegate` conforms to `NSObjectProtocol`, which no actor can
/// satisfy. The two delegate methods are `nonisolated` (the system calls them off the
/// main thread) and hop to `@MainActor` only where needed.
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

    /// Provisional authorization: notifications land quietly in Notification Center with no
    /// upfront prompt, so this is safe to call on the first background failure rather than
    /// at launch, where prompting just trains the user to deny.
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

    /// Post (or replace) the build-failure notification. Coalescing per burst is the caller's
    /// job - `HugoServerService` invokes this on the empty -> non-empty transition only.
    /// The fixed identifier is a second line of defence.
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

    /// Bring Victor to the front. Deep-linking into the Build Issues popover would need a
    /// shared observable flag on `SiteViewModel` - the presentation flag today is private
    /// `@State` in `ServerControlView` - so this activates the app only.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
