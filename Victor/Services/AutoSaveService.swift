import Foundation

/// Service for handling auto-save with debouncing and conflict detection
actor AutoSaveService {
    static let shared = AutoSaveService()

    /// Pending debounced saves keyed by file URL.
    /// Per-file tasks so editing one file never cancels another file's pending save.
    private var saveTasks: [URL: Task<Void, Never>] = [:]

    /// Current generation token per file (see clearFinishedTask)
    private var saveTokens: [URL: UUID] = [:]

    /// Debounce interval honors the user's "Save after:" preference
    private var debounceInterval: TimeInterval {
        AppSettings.currentAutoSaveDelay()
    }

    private init() {}

    /// Schedule an auto-save operation with debouncing
    /// - Parameters:
    ///   - fileURL: URL of the file to save
    ///   - content: Content to save
    ///   - lastModified: Last known modification date (for conflict detection)
    ///   - onConflict: Callback when a conflict is detected
    ///   - onSuccess: Callback when save succeeds
    ///   - onError: Callback when save fails
    ///
    /// Callback parameters are `@Sendable @MainActor` (WP3.5 Cluster 8): `@MainActor`
    /// alone says where the closure runs, but doesn't make the closure *value* legal
    /// to store in this actor's isolated state - that's what `@Sendable` is for. No
    /// call-site changes needed: callers' closures already only capture `weak self`
    /// plus Sendable primitives (`UUID`/`URL`), which already satisfies `@Sendable`.
    func scheduleAutoSave(
        fileURL: URL,
        content: String,
        lastModified: Date,
        onConflict: @escaping @Sendable @MainActor () -> ConflictResolution,
        onSuccess: @escaping @Sendable @MainActor (Date) -> Void,
        onError: @escaping @Sendable @MainActor (Error) -> Void
    ) {
        // Cancel any pending save for this file only
        saveTasks[fileURL]?.cancel()

        // Generation token so a finished task only cleans up its own dictionary
        // entry, never a newer task scheduled for the same file
        let token = UUID()
        saveTokens[fileURL] = token

        // Schedule new save after debounce interval
        let task = Task {
            do {
                // Wait for debounce interval
                try await Task.sleep(for: .seconds(debounceInterval))

                // Check if task was cancelled
                guard !Task.isCancelled else { return }

                // Perform the save
                let newModificationDate = try await performSave(
                    fileURL: fileURL,
                    content: content,
                    lastModified: lastModified,
                    onConflict: onConflict
                )

                // Notify success on main actor
                await onSuccess(newModificationDate)
            } catch is CancellationError {
                // Task was cancelled, ignore
            } catch {
                // Notify error on main actor
                await onError(error)
            }
            clearFinishedTask(for: fileURL, token: token)
        }
        saveTasks[fileURL] = task
    }

    /// Remove the completed task entry unless it was already replaced by a newer schedule
    private func clearFinishedTask(for fileURL: URL, token: UUID) {
        guard saveTokens[fileURL] == token else { return }
        saveTokens.removeValue(forKey: fileURL)
        saveTasks.removeValue(forKey: fileURL)
    }

    /// Cancel the pending auto-save for a specific file
    func cancelAutoSave(for fileURL: URL) {
        saveTasks[fileURL]?.cancel()
        saveTasks.removeValue(forKey: fileURL)
        saveTokens.removeValue(forKey: fileURL)
    }

    /// Cancel all pending auto-saves
    func cancelAutoSave() {
        for task in saveTasks.values {
            task.cancel()
        }
        saveTasks.removeAll()
        saveTokens.removeAll()
    }

    /// Perform the actual save operation with conflict detection
    private func performSave(
        fileURL: URL,
        content: String,
        lastModified: Date,
        onConflict: @escaping @Sendable @MainActor () -> ConflictResolution
    ) async throws -> Date {
        // Check for conflicts (file modified externally)
        let currentModificationDate = try await getFileModificationDate(url: fileURL)

        if currentModificationDate > lastModified {
            // Modification date changed - check if content actually differs
            let currentContent = try await getFileContent(url: fileURL)

            // Only show conflict if content is actually different
            if currentContent != content {
                // Real conflict detected - file was modified externally with different content
                let resolution = await onConflict()

                switch resolution {
                case .keepLocal:
                    // User wants to overwrite with local changes
                    break
                case .reloadFromDisk:
                    // User wants to discard local changes and reload from disk
                    throw AutoSaveError.userCancelledDueToConflict
                case .cancel:
                    // User cancelled the save
                    throw AutoSaveError.userCancelledDueToConflict
                }
            }
            // If content is the same, no conflict - just proceed with save
        }

        // Perform the save with NSFileCoordinator (victor-mod: shared `withFileCoordination`
        // helper replaces the hand-rolled continuation + didResume dance)
        return try await withFileCoordination { resume in
            let coordinator = NSFileCoordinator()
            var coordinatorError: NSError?

            coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinatorError) { url in
                do {
                    // Write directly (not atomically) so Hugo's file watcher can detect
                    // which file changed for --navigateToChanged. Atomic writes use rename
                    // which Hugo can't associate with the content file path.
                    // Risk is minimal since Hugo content is typically git-tracked.
                    try content.write(to: url, atomically: false, encoding: .utf8)

                    // Get new modification date
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    let newModificationDate = attributes[.modificationDate] as? Date ?? Date()

                    resume(.success(newModificationDate))
                } catch {
                    resume(.failure(error))
                }
            }

            return coordinatorError
        }
    }

    /// Get the modification date of a file, off the actor.
    /// `nonisolated` + `@concurrent` replaces `Task.detached` here (victor-tdt audit):
    /// this private method was actor-isolated purely by inheriting `AutoSaveService`'s
    /// isolation, not because it touches any actor state. `@concurrent` (SE-0461)
    /// compiler-pins this to the concurrent executor - verified to compile in this
    /// project's Swift 6.0 language mode with no upcoming-feature flag - so the blocking
    /// `FileManager` call is guaranteed off the actor regardless of the
    /// `NonisolatedNonsendingByDefault` setting, not merely under today's default.
    @concurrent
    private nonisolated func getFileModificationDate(url: URL) async throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.modificationDate] as? Date ?? Date()
    }

    /// Get the current content of a file, off the actor (see `getFileModificationDate`
    /// above). `@concurrent` here is belt-and-suspenders: this method's own body just
    /// awaits the already-`@concurrent` `readFileContentsOffActor`, but pinning it too
    /// keeps the guarantee compiler-enforced at every layer, not just the leaf call.
    @concurrent
    private nonisolated func getFileContent(url: URL) async throws -> String {
        try await readFileContentsOffActor(at: url)
    }
}

// MARK: - Conflict Resolution

/// How to resolve a save conflict
enum ConflictResolution {
    case keepLocal      // Overwrite file with local changes
    case reloadFromDisk // Discard local changes and reload from disk
    case cancel         // Cancel the save operation
}

// MARK: - Auto-Save Errors

enum AutoSaveError: LocalizedError {
    case userCancelledDueToConflict
    case fileModifiedExternally

    var errorDescription: String? {
        switch self {
        case .userCancelledDueToConflict:
            return "Save cancelled due to conflict"
        case .fileModifiedExternally:
            return "File was modified by another application"
        }
    }
}
