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
        UserDefaults.standard.object(forKey: AppConstants.UserDefaultsKeys.autoSaveDelay) as? Double
            ?? AppConstants.AutoSave.debounceInterval
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
    func scheduleAutoSave(
        fileURL: URL,
        content: String,
        lastModified: Date,
        onConflict: @escaping @MainActor () -> ConflictResolution,
        onSuccess: @escaping @MainActor (Date) -> Void,
        onError: @escaping @MainActor (Error) -> Void
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
        onConflict: @escaping @MainActor () -> ConflictResolution
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

        // Perform the save with NSFileCoordinator
        return try await withCheckedThrowingContinuation { continuation in
            let coordinator = NSFileCoordinator()
            var coordinatorError: NSError?
            var didResume = false

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

                    continuation.resume(returning: newModificationDate)
                    didResume = true
                } catch {
                    continuation.resume(throwing: error)
                    didResume = true
                }
            }

            // Only resume here if the coordination block was never executed
            // (coordinatorError is set when coordination fails before the block runs)
            if !didResume, let error = coordinatorError {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Get the modification date of a file (runs on background thread)
    private func getFileModificationDate(url: URL) async throws -> Date {
        try await Task.detached {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.modificationDate] as? Date ?? Date()
        }.value
    }

    /// Get the current content of a file (runs on background thread)
    private func getFileContent(url: URL) async throws -> String {
        try await Task.detached {
            try String(contentsOf: url, encoding: .utf8)
        }.value
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
