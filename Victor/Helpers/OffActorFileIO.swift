import Foundation

/// Shared helper for the "blocking read, must leave the caller's actor" shape that appeared
/// identically across ~6 `Task.detached` call sites (victor-tdt audit).
///
/// `@concurrent` (SE-0461) pins this to the concurrent executor at the compiler level,
/// rather than relying on today's `NonisolatedNonsendingByDefault` value - this toolchain
/// ships the upcoming feature that flips that default. Unlike `Task.detached`, the call
/// stays inside the caller's structured task, so priority, task-locals and cancellation
/// all still propagate.

/// Reads a file's full contents as a string, off the caller's actor.
@concurrent
nonisolated func readFileContentsOffActor(
    at url: URL,
    encoding: String.Encoding = .utf8
) async throws -> String {
    try String(contentsOf: url, encoding: encoding)
}
