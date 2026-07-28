import Foundation

/// Service for handling auto-save with debouncing and conflict detection
actor AutoSaveService {
    /// Non-private (victor-zw4): tests construct their own instance for
    /// isolation from the process-wide singleton (fresh actor per test = no
    /// cross-test interference via shared pending-save state). Construction
    /// is side-effect-free — no I/O, no UserDefaults read.
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

    init() {}

    /// Debounced auto-save. `lastModified` is the date conflict detection compares against.
    ///
    /// Callbacks are `@Sendable @MainActor`: `@MainActor` says where they run,
    /// `@Sendable` is what makes the closure value legal to store in this actor's state.
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

    /// Conflict-checked save without this actor's own debounce - `EditorViewModel` owns a
    /// MainActor debounce and builds the full document once at fire time, so the wait is
    /// already over by the time it calls this. Still reuses `performSave`.
    ///
    /// `scheduleAutoSave` above is unused in production but kept: it's correct, covered,
    /// and its URL-keyed `saveTasks` are a separate subsystem from the node-ID registry
    /// below, which is what rename/move actually use.
    func scheduleImmediateSave(
        fileURL: URL,
        content: String,
        lastModified: Date,
        onConflict: @escaping @Sendable @MainActor () -> ConflictResolution,
        onSuccess: @escaping @Sendable @MainActor (Date) -> Void,
        onError: @escaping @Sendable @MainActor (Error) -> Void
    ) async {
        // Supersede any still-pending debounced save for this file (defensive -
        // callers aren't expected to mix the two paths for the same URL, but this
        // guarantees exactly one write wins if they ever do).
        saveTasks[fileURL]?.cancel()
        saveTasks.removeValue(forKey: fileURL)
        saveTokens.removeValue(forKey: fileURL)

        do {
            let newModificationDate = try await performSave(
                fileURL: fileURL,
                content: content,
                lastModified: lastModified,
                onConflict: onConflict
            )
            await onSuccess(newModificationDate)
        } catch is CancellationError {
            // Caller's own Task was cancelled (e.g. superseded by a newer debounce) - ignore
        } catch {
            await onError(error)
        }
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

    // MARK: - Node-Keyed Debounce Registry (victor-rnm TOCTOU hardening)
    //
    // The `cancelAutoSave(for:)` calls rename/move used to make were dead - nothing in
    // production registers into `saveTasks`. That left a real TOCTOU: a rename landing
    // while an editor's local debounce Task was already past its own cancellation check
    // could still write to the pre-rename path, recreating the file there.
    //
    // Callers now register their debounce Task under the FileNode.id it saves for
    // (stable across rename/move, unlike a URL), and `cancelDebounce(nodeID:)` awaits
    // the Task's completion rather than just calling `.cancel()` and hoping.

    /// Debounce Tasks owned by callers (EditorViewModel/TextEditorViewModel),
    /// keyed by the FileNode.id they save for - NOT the URL-keyed `saveTasks`
    /// above, which only `scheduleAutoSave` writes into.
    private var debounceTasksByNodeID: [UUID: Task<Void, Never>] = [:]

    /// Generation token per nodeID, same pattern as `saveTokens` above: a
    /// keystroke reschedule overwrites this entry with a new Task+token before
    /// the superseded Task gets a chance to run its own (now-stale)
    /// `deregisterDebounce` call - the token stops that stale call from
    /// clobbering the newer registration.
    private var debounceTokensByNodeID: [UUID: UUID] = [:]

    /// Number of currently-registered debounce Tasks - test-visible hook for
    /// asserting registry hygiene (no unbounded growth once debounces
    /// complete/get cancelled).
    var debounceRegistrationCount: Int {
        debounceTasksByNodeID.count
    }

    /// Register a caller-owned debounce Task under `nodeID`, with a
    /// caller-generated `token` (see `deregisterDebounce`). Overwrites any
    /// previous registration for the same nodeID - callers re-register on
    /// every keystroke reschedule, mirroring their own `.cancel()`-then-replace
    /// of their local Task reference.
    func registerDebounce(nodeID: UUID, token: UUID, task: Task<Void, Never>) {
        debounceTasksByNodeID[nodeID] = task
        debounceTokensByNodeID[nodeID] = token
    }

    /// Remove a debounce registration once its Task is done running (whether it
    /// completed a write or exited early after cancellation) - callers call this
    /// as the LAST action in their Task body, unconditionally, so the registry
    /// never grows unbounded. No-op if a newer Task has already replaced this
    /// registration for the same nodeID (token mismatch) - see `registerDebounce`.
    func deregisterDebounce(nodeID: UUID, token: UUID) {
        guard debounceTokensByNodeID[nodeID] == token else { return }
        debounceTasksByNodeID.removeValue(forKey: nodeID)
        debounceTokensByNodeID.removeValue(forKey: nodeID)
    }

    /// Cancel the debounce registered for `nodeID` and WAIT for it to finish. Cancellation
    /// is cooperative, and the Task may already be past its own check and into a write
    /// that doesn't observe cancellation - awaiting `task.value` leaves no window.
    ///
    /// Loops rather than a single cancel-and-await: a new debounce registered for the
    /// same node while we awaited the previous one isn't safe to leave pending either.
    func cancelDebounce(nodeID: UUID) async {
        while let task = debounceTasksByNodeID[nodeID] {
            task.cancel()
            await task.value
        }
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

    /// Get the modification date of a file, off the actor. This was actor-isolated only by
    /// inheriting the enclosing isolation; `@concurrent` pins the blocking `FileManager`
    /// call to the concurrent executor.
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
