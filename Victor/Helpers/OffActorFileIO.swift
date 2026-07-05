import Foundation

/// Shared helper for the "blocking read, must leave the caller's actor" shape that
/// showed up identically across ~6 `Task.detached` call sites (victor-tdt audit).
///
/// `@concurrent` (SE-0461, available on this toolchain in Swift 6.0 language mode -
/// verified, no upcoming-feature flag needed) pins this function to the concurrent
/// executor at the compiler level: it always runs off whatever actor called it,
/// regardless of the `NonisolatedNonsendingByDefault` setting. Phase review flagged
/// that relying on today's default (`false`, where plain `nonisolated async` also hops
/// off) was fragile - this toolchain ships the upcoming feature that flips that
/// default, and `@concurrent` is the mechanism SE-0461 introduces specifically to keep
/// "must leave the actor" pinned even after the flip. That gives the same "off the main
/// actor" effect `Task.detached` does, but keeps the call inside the caller's structured
/// task, so priority, task-locals, and cancellation all still propagate (a genuinely
/// `detached` task gets none of those).
///
/// Callers that are themselves `@MainActor` (or otherwise actor-isolated) can `await`
/// this directly to get off their actor for the blocking read; callers that are already
/// `nonisolated` (e.g. `HugoConfigParser`'s methods) don't need it at all - see the
/// per-site notes left at each converted call site.

/// Reads a file's full contents as a string, off the caller's actor.
@concurrent
nonisolated func readFileContentsOffActor(
    at url: URL,
    encoding: String.Encoding = .utf8
) async throws -> String {
    try String(contentsOf: url, encoding: encoding)
}
