import Foundation

/// Service for handling auto-save with debouncing and conflict detection
actor AutoSaveService {
    static let shared = AutoSaveService()

    private var saveTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval = 2.0 // 2 seconds

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
        // Cancel any pending save
        saveTask?.cancel()

        // Schedule new save after debounce interval
        saveTask = Task {
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
        }
    }

    /// Cancel any pending auto-save
    func cancelAutoSave() {
        saveTask?.cancel()
        saveTask = nil
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

            coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinatorError) { url in
                do {
                    // Write the content
                    try content.write(to: url, atomically: true, encoding: .utf8)

                    // Get new modification date
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    let newModificationDate = attributes[.modificationDate] as? Date ?? Date()

                    continuation.resume(returning: newModificationDate)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            if let error = coordinatorError {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Get the modification date of a file
    private func getFileModificationDate(url: URL) async throws -> Date {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let modificationDate = attributes[.modificationDate] as? Date ?? Date()
                continuation.resume(returning: modificationDate)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Get the current content of a file
    private func getFileContent(url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                continuation.resume(returning: content)
            } catch {
                continuation.resume(throwing: error)
            }
        }
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
