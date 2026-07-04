import Foundation

/// Shared helper for the "blocking read, must leave the caller's actor" shape that
/// showed up identically across ~6 `Task.detached` call sites (victor-tdt audit).
///
/// `nonisolated` + `async` is enough on its own to leave the caller's actor: under
/// this project's current build settings (no `NonisolatedNonsendingByDefault` upcoming
/// feature enabled - see `project.yml`), a `nonisolated async` function always hops off
/// the caller's actor to run, then hops back on return - verified empirically for this
/// audit, not assumed. That gives the same "off the main actor" effect `Task.detached`
/// does, but keeps the call inside the caller's structured task, so priority, task-locals,
/// and cancellation all still propagate (a genuinely `detached` task gets none of those).
///
/// Callers that are themselves `@MainActor` (or otherwise actor-isolated) can `await`
/// this directly to get off their actor for the blocking read; callers that are already
/// `nonisolated` (e.g. `HugoConfigParser`'s methods) don't need it at all - see the
/// per-site notes left at each converted call site.

/// Reads a file's full contents as a string, off the caller's actor.
nonisolated func readFileContentsOffActor(
    at url: URL,
    encoding: String.Encoding = .utf8
) async throws -> String {
    try String(contentsOf: url, encoding: encoding)
}
