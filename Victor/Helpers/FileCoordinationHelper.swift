import Foundation
import os

/// Dedupes the `withCheckedThrowingContinuation` + `didResume` dance that used to be
/// hand-rolled identically in three places: `AutoSaveService.performSave`,
/// `FileSystemService.renameFile`, and `FileSystemService.duplicateFile` (victor-mod
/// grab-bag item 3). All three follow the same shape:
///
///   1. Call `NSFileCoordinator.coordinate(...)`, which synchronously invokes an
///      accessor block (or fails up front and sets an `NSError` out-param).
///   2. The accessor block does the actual file operation and must resume a
///      continuation with success or failure.
///   3. If coordination fails *before* the accessor block ever runs, resume with
///      the `NSError` instead - but only if the block didn't already resume.
///
/// This function owns the continuation and the `didResume` guard; each call site still
/// picks its own `coordinate(...)` overload (single vs. dual URL, reading vs. writing
/// options), since those differ per site and aren't worth abstracting further.
///
/// `didResume` is guarded by `OSAllocatedUnfairLock` rather than a plain captured `var`:
/// `resume` is `@Sendable` (it may be invoked from whatever thread `NSFileCoordinator`
/// calls the accessor block on), so a bare mutable capture doesn't type-check under
/// Swift 6 strict concurrency (verified - a plain `var didResume` capture is rejected
/// with "mutation of captured var in concurrently-executing code").
///
/// - Parameter body: Performs the actual `NSFileCoordinator.coordinate(...)` call.
///   It's given a `resume` closure to report the accessor block's result, and must
///   return the `NSError?` produced by `coordinate`'s `error:` out-parameter (`nil`
///   if coordination didn't fail up front).
/// - Returns: Whatever `resume` was called with on success.
/// - Throws: Whatever `resume` was called with on failure, or the coordinator's own
///   error if the accessor block never ran.
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
