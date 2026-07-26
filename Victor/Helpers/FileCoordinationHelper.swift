import Foundation
import os

/// Dedupes the `withCheckedThrowingContinuation` + `didResume` dance hand-rolled
/// identically in `AutoSaveService.performSave` and `FileSystemService.renameFile`/
/// `duplicateFile`: coordinate, let the accessor block resume, and resume with the
/// coordinator's own error if the block never ran. Each call site still picks its own
/// `coordinate(...)` overload.
///
/// `didResume` uses `OSAllocatedUnfairLock` rather than a captured `var` because `resume`
/// is `@Sendable` - a bare mutable capture doesn't type-check under Swift 6.
///
/// - Parameter body: performs the `coordinate(...)` call, given a `resume` closure, and
///   returns the `NSError?` from `coordinate`'s `error:` out-parameter.
/// - Returns: whatever `resume` was called with on success.
/// - Throws: whatever `resume` was called with, or the coordinator's own error.
///
/// `@concurrent` pins this - and transitively each `body`'s blocking `coordinate(...)` -
/// to the concurrent executor, so callers don't need `@concurrent` themselves.
@concurrent
nonisolated func withFileCoordination<T: Sendable>(
    _ body: (_ resume: @escaping @Sendable (Result<T, Error>) -> Void) -> NSError?
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let didResume = OSAllocatedUnfairLock(initialState: false)

        // Claims the "resume" right exactly once; returns whether this caller won it.
        let claimResume: @Sendable () -> Bool = {
            didResume.withLock { resumed in
                guard !resumed else { return false }
                resumed = true
                return true
            }
        }

        let resume: @Sendable (Result<T, Error>) -> Void = { result in
            guard claimResume() else { return }
            continuation.resume(with: result)
        }

        let coordinatorError = body(resume)

        // Only resume here if the accessor block never ran (coordinatorError is set
        // when coordination fails before the block executes).
        if let error = coordinatorError, claimResume() {
            continuation.resume(throwing: error)
        }
    }
}
