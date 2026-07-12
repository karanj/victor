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

    /// Perform a conflict-checked save immediately, without this actor's own debounce.
    ///
    /// (Perf ticket, post-victor-zw4): `EditorViewModel` now owns its own MainActor
    /// debounce Task (reading `AppSettings.currentAutoSaveDelay()` directly) and builds
    /// the full document - frontmatter serialization + markdown concat - exactly once,
    /// at fire time, from LIVE state, rather than on every keystroke. By the time that
    /// Task calls this method the wait is already over, so debouncing again here would
    /// just add a second, redundant delay. This still reuses `performSave` for the
    /// conflict-detection/`NSFileCoordinator` write - only the debounce wrapper is
    /// skipped.
    ///
    /// `scheduleAutoSave` (above) is kept rather than removed or converted: nothing
    /// currently calls it (TextEditorViewModel was never wired to `AutoSaveService` -
    /// it has always had its own separate hand-rolled MainActor debounce + direct
    /// `FileSystemService.writeFile` call, with no conflict detection), so there's no
    /// compatibility need to preserve. It's kept because it's still correct, still
    /// covered by AutoSaveServiceTests, and deleting/rewriting working, tested code
    /// purely to shrink the file isn't worth the churn this session - see the
    /// implementation report for victor's keystroke-lag fix. Its URL-keyed
    /// `saveTasks`/`cancelAutoSave(for:)` are a self-contained subsystem, separate
    /// from the node-ID-keyed debounce registry below - SiteViewModel.renameFile/
    /// moveNode use the latter, not this one, since nothing registers into
    /// `saveTasks` in production (see the registry's intro comment for the story).
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
    // Program review after victor-rnm shipped found the `cancelAutoSave(for:)`
    // calls SiteViewModel.renameFile/moveNode made were dead: nothing in
    // production calls `scheduleAutoSave` above (see its doc comment) - only
    // EditorViewModel/TextEditorViewModel's own LOCAL per-keystroke debounce
    // Tasks exist in production, and those were never registered anywhere this
    // actor could reach. That left a real TOCTOU: a rename/move landing while
    // one of those local Tasks was already past its own cancellation check and
    // into `scheduleImmediateSave`/`performSave` (both of which run on THIS
    // actor's executor, not the caller's MainActor, and don't check
    // `Task.isCancelled` themselves) could still write to the pre-rename path
    // after the rename completed - recreating the file there with rename's
    // node-id-preserving semantics masking the corruption (staleness guards
    // pass, "Saved" shows, but Hugo now sees two content files).
    //
    // This registry closes that structurally: callers register their own debounce
    // Task under the FileNode.id it saves for (stable across rename/move, unlike
    // a URL key), and `cancelDebounce(nodeID:)` doesn't just call `.cancel()` and
    // hope - it AWAITS the Task's actual completion before returning, so a caller
    // like SiteViewModel.renameFile can't proceed with the disk op until any
    // in-flight write for that node has either been stopped (still sleeping) or
    // has fully landed (already writing - lands at the pre-rename path, which is
    // still valid at that moment, and the rename then carries that fresh content
    // forward).

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

    /// Cancel the debounce Task registered for `nodeID` (if any) and WAIT for it
    /// to actually finish before returning - not just call `.cancel()` and move
    /// on. Cancellation is cooperative: by the time a caller reaches this, the
    /// Task may already be past its own `Task.isCancelled` check and into a
    /// write that doesn't itself observe cancellation (see this section's intro
    /// comment). Awaiting `task.value` blocks until the Task is completely done
    /// either way, so there is no window left for a write to land after this
    /// method returns.
    ///
    /// Loops rather than a single cancel-and-await: if a NEW debounce gets
    /// registered for the same nodeID while we were awaiting the previous one
    /// (e.g. a keystroke lands during the await), that new registration isn't
    /// safe to leave pending either - re-checking the registry after each await
    /// picks it up too, converging once nothing re-registers.
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
