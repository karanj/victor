import Foundation
import AppKit

// MARK: - Hugo Server Status

/// Represents the current state of the Hugo development server
enum HugoServerStatus: Equatable {
    case stopped
    case starting
    case running(port: Int)
    case error(message: String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var displayText: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting..."
        case .running(let port):
            return "Running on port \(port)"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

// MARK: - Hugo Server Configuration

/// Configuration options for the Hugo development server
struct HugoServerConfig: Equatable {
    /// Port number for the server (default: 1313)
    var port: Int = 1313

    /// Bind address (default: localhost)
    var bindAddress: String = "localhost"

    /// Include draft content
    var buildDrafts: Bool = true

    /// Include future-dated content
    var buildFuture: Bool = true

    /// Include expired content
    var buildExpired: Bool = false

    /// Enable file watching for live reload
    var watch: Bool = true

    /// Navigate to changed content file in browser
    var navigateToChanged: Bool = true

    /// Disable live browser reload
    var disableLiveReload: Bool = false

    /// Build a config seeded from the user's Preferences ("Server Defaults").
    /// Only keys the user has actually set override the built-in defaults.
    static func fromUserDefaults(_ defaults: UserDefaults = .standard) -> HugoServerConfig {
        var config = HugoServerConfig()
        let port = AppSettings.currentHugoServerPort()
        if (1024...65535).contains(port) {
            config.port = port
        }
        config.buildDrafts = AppSettings.currentHugoServerBuildDrafts()
        config.buildFuture = AppSettings.currentHugoServerBuildFuture()
        config.buildExpired = AppSettings.currentHugoServerBuildExpired()
        return config
    }
}

// MARK: - Build Error

/// Represents a Hugo build error or warning
struct HugoBuildError: Identifiable, Equatable {
    let id = UUID()
    let level: Level
    let message: String
    let file: String?
    let line: Int?
    let timestamp: Date

    enum Level: String {
        case error = "ERROR"
        case warning = "WARN"
        case info = "INFO"
    }

    /// Try to extract a clickable file path from the error
    var clickableFilePath: String? {
        guard let file = file else { return nil }
        if let line = line {
            return "\(file):\(line)"
        }
        return file
    }
}

// MARK: - Hugo Server Service

/// Actor-based service for managing Hugo development server subprocess
actor HugoServerService {
    static let shared = HugoServerService()

    // MARK: - Published State (accessed via async getters)

    private(set) var status: HugoServerStatus = .stopped
    private(set) var config: HugoServerConfig = HugoServerConfig.fromUserDefaults()
    private(set) var buildErrors: [HugoBuildError] = []
    private(set) var serverOutput: [String] = []
    private(set) var serverURL: URL?

    // MARK: - Private Properties

    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var siteRootURL: URL?

    /// Maximum lines of output to keep in memory
    private let maxOutputLines = 500

    /// Crash recovery tracking
    private var crashRecoveryAttempts = 0
    private let maxCrashRecoveryAttempts = 3

    /// Callbacks for state changes (main actor) - supports multiple observers
    private var statusChangeCallbacks: [UUID: @MainActor (HugoServerStatus) -> Void] = [:]
    private var buildErrorsChangeCallbacks: [UUID: @MainActor ([HugoBuildError]) -> Void] = [:]
    private var outputChangeCallbacks: [UUID: @MainActor ([String]) -> Void] = [:]

    private init() {}

    // MARK: - Configuration

    /// Update server configuration
    func updateConfig(_ newConfig: HugoServerConfig) {
        config = newConfig
    }

    /// Add callback for status changes, returns ID to remove later
    @discardableResult
    func addOnStatusChange(_ callback: @escaping @MainActor (HugoServerStatus) -> Void) -> UUID {
        let id = UUID()
        statusChangeCallbacks[id] = callback
        return id
    }

    /// Remove a status change callback
    func removeOnStatusChange(_ id: UUID) {
        statusChangeCallbacks.removeValue(forKey: id)
    }

    /// Add callback for build errors changes, returns ID to remove later
    @discardableResult
    func addOnBuildErrorsChange(_ callback: @escaping @MainActor ([HugoBuildError]) -> Void) -> UUID {
        let id = UUID()
        buildErrorsChangeCallbacks[id] = callback
        return id
    }

    /// Remove a build errors change callback
    func removeOnBuildErrorsChange(_ id: UUID) {
        buildErrorsChangeCallbacks.removeValue(forKey: id)
    }

    /// Add callback for output changes, returns ID to remove later
    @discardableResult
    func addOnOutputChange(_ callback: @escaping @MainActor ([String]) -> Void) -> UUID {
        let id = UUID()
        outputChangeCallbacks[id] = callback
        return id
    }

    /// Remove an output change callback
    func removeOnOutputChange(_ id: UUID) {
        outputChangeCallbacks.removeValue(forKey: id)
    }

    // Legacy single-callback methods for backwards compatibility
    func setOnStatusChange(_ callback: @escaping @MainActor (HugoServerStatus) -> Void) {
        addOnStatusChange(callback)
    }

    func setOnBuildErrorsChange(_ callback: @escaping @MainActor ([HugoBuildError]) -> Void) {
        addOnBuildErrorsChange(callback)
    }

    func setOnOutputChange(_ callback: @escaping @MainActor ([String]) -> Void) {
        addOnOutputChange(callback)
    }

    // MARK: - Hugo Binary Detection

    /// Check if Hugo is installed and accessible
    func isHugoInstalled() async -> Bool {
        let path = await findHugoBinary()
        return path != nil
    }

    /// Find the Hugo binary path
    func findHugoBinary() async -> String? {
        // Common Hugo installation paths
        let paths = [
            "/usr/local/bin/hugo",
            "/opt/homebrew/bin/hugo",
            "/usr/bin/hugo",
            "\(NSHomeDirectory())/go/bin/hugo",
            "\(NSHomeDirectory())/.local/bin/hugo"
        ]

        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Try to find via 'which hugo'
        return await findBinaryViaWhich("hugo")
    }

    /// Allowed directory prefixes for binary paths (security measure)
    private static let allowedBinaryPrefixes = [
        "/usr/local/bin/",
        "/opt/homebrew/bin/",
        "/usr/bin/",
        "\(NSHomeDirectory())/go/bin/",
        "\(NSHomeDirectory())/.local/bin/"
    ]

    /// Find binary path using 'which' command
    private func findBinaryViaWhich(_ binary: String) async -> String? {
        // Security: Validate binary name contains only safe characters (alphanumeric, hyphens, underscores)
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard binary.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            Logger.shared.warning("[HugoServer] Invalid binary name rejected: \(binary)")
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [binary]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let path = output, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                // Security: Validate path is in an allowed directory
                let isAllowedPath = Self.allowedBinaryPrefixes.contains { prefix in
                    path.hasPrefix(prefix)
                }

                guard isAllowedPath else {
                    Logger.shared.warning("[HugoServer] Binary found in unexpected location, rejecting: \(path)")
                    return nil
                }

                return path
            }
        } catch {
            Logger.shared.debug("Failed to find \(binary) via which: \(error.localizedDescription)")
        }

        return nil
    }

    /// Get Hugo version string
    func getHugoVersion() async -> String? {
        guard let hugoPath = await findHugoBinary() else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: hugoPath)
        process.arguments = ["version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            Logger.shared.debug("Failed to get Hugo version: \(error.localizedDescription)")
        }

        return nil
    }

    // MARK: - Server Control

    /// Start the Hugo development server
    func start(siteURL: URL) async throws {
        // Don't start if already running
        guard !status.isRunning else {
            Logger.shared.info("[HugoServer] Server already running")
            return
        }

        // Check if Hugo is installed
        guard let hugoPath = await findHugoBinary() else {
            let error = HugoServerError.hugoNotFound
            await updateStatus(.error(message: error.localizedDescription))
            throw error
        }

        // Check if port is available
        if await !isPortAvailable(config.port) {
            // Try to find an available port
            if let availablePort = await findAvailablePort(startingFrom: config.port) {
                config.port = availablePort
                Logger.shared.info("[HugoServer] Port conflict, using port \(availablePort)")
            } else {
                let error = HugoServerError.portInUse(config.port)
                await updateStatus(.error(message: error.localizedDescription))
                throw error
            }
        }

        siteRootURL = siteURL
        await updateStatus(.starting)

        // Clear previous output and errors
        serverOutput = []
        buildErrors = []
        await notifyOutputChange()
        await notifyBuildErrorsChange()

        // Build command arguments
        var args = ["server"]
        args.append("--port=\(config.port)")
        args.append("--bind=\(config.bindAddress)")

        if config.buildDrafts {
            args.append("--buildDrafts")
        }
        if config.buildFuture {
            args.append("--buildFuture")
        }
        if config.buildExpired {
            args.append("--buildExpired")
        }
        if !config.watch {
            args.append("--watch=false")
        }
        if config.navigateToChanged {
            args.append("--navigateToChanged")
        }
        if config.disableLiveReload {
            args.append("--disableLiveReload")
        }

        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: hugoPath)
        process.arguments = args
        process.currentDirectoryURL = siteURL

        // Set up pipes for output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        self.process = process
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe

        // Set up output handlers
        setupOutputHandlers(outputPipe: outputPipe, errorPipe: errorPipe)

        // Handle process termination
        process.terminationHandler = { [weak self] terminatedProcess in
            Task { [weak self] in
                await self?.handleProcessTermination(exitCode: terminatedProcess.terminationStatus)
            }
        }

        do {
            try process.run()
            Logger.shared.info("[HugoServer] Started Hugo server with args: \(args.joined(separator: " "))")

            // Set server URL
            serverURL = URL(string: "http://\(config.bindAddress):\(config.port)")

        } catch {
            await updateStatus(.error(message: error.localizedDescription))
            throw HugoServerError.startFailed(error.localizedDescription)
        }
    }

    /// Stop the Hugo development server
    func stop() async {
        guard let process = process, process.isRunning else {
            await updateStatus(.stopped)
            return
        }

        Logger.shared.info("[HugoServer] Stopping server...")

        // Stop pumping output before tearing down, so the pipes' file handles
        // are released and no stray reads fire after stop
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil

        // Send SIGTERM for graceful shutdown
        process.terminate()

        // Wait briefly for graceful shutdown
        try? await Task.sleep(for: .milliseconds(500))

        // Force kill if still running (SIGINT would be weaker than the SIGTERM already sent)
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }

        self.process = nil
        self.outputPipe = nil
        self.errorPipe = nil
        serverURL = nil

        await updateStatus(.stopped)
        Logger.shared.info("[HugoServer] Server stopped")
    }

    /// Restart the Hugo development server
    func restart(siteURL: URL) async throws {
        await stop()
        try? await Task.sleep(for: .milliseconds(300))
        try await start(siteURL: siteURL)
    }

    // MARK: - Output Handling

    private func setupOutputHandlers(outputPipe: Pipe, errorPipe: Pipe) {
        // Handle stdout
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            if let output = String(data: data, encoding: .utf8) {
                Task { [weak self] in
                    await self?.processOutput(output, isError: false)
                }
            }
        }

        // Handle stderr
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            if let output = String(data: data, encoding: .utf8) {
                Task { [weak self] in
                    await self?.processOutput(output, isError: true)
                }
            }
        }
    }

    private func processOutput(_ output: String, isError: Bool) async {
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }

        for line in lines {
            // Add to output log
            serverOutput.append(line)
            if serverOutput.count > maxOutputLines {
                serverOutput.removeFirst()
            }

            // Parse the line for status and errors
            await parseLine(line)
        }

        await notifyOutputChange()
    }

    private func parseLine(_ line: String) async {
        // Use BuildErrorParser for server ready detection
        if let port = BuildErrorParser.parseServerReady(line) {
            await updateStatus(.running(port: port))
            return
        }

        // Check for rebuild notification - clear errors
        if BuildErrorParser.isRebuildingLine(line) {
            buildErrors = []
            await notifyBuildErrorsChange()
            return
        }

        // Check for build completion
        if let buildTime = BuildErrorParser.parseBuildComplete(line) {
            Logger.shared.debug("[HugoServer] Build completed in \(buildTime)ms")
            return
        }

        // Use BuildErrorParser for error/warning detection
        if let error = BuildErrorParser.parseLine(line) {
            let hadFailureBefore = buildErrors.contains { $0.level == .error }
            buildErrors.append(error)
            await notifyBuildErrorsChange()

            // New failing build: the first `.error`-level line since the
            // last rebuild cleared `buildErrors` (see isRebuildingLine
            // above). Warnings alone don't count as a "failure".
            if error.level == .error && !hadFailureBefore {
                await notifyBackgroundBuildFailureIfNeeded()
            }
        }
    }

    /// Post a background build-failure notification if: the setting is on,
    /// Victor isn't the active app, and this is a new failure (see call
    /// site). Foreground failures rely on `BuildErrorOverlay` instead
    /// (Docs/MAC-POLISH-DESIGN.md W3.4).
    private func notifyBackgroundBuildFailureIfNeeded() async {
        guard AppSettings.currentNotifyOnBuildFailure() else { return }

        let errorCount = buildErrors.filter { $0.level == .error }.count
        guard let firstError = buildErrors.first(where: { $0.level == .error }) else { return }

        // NSApp.isActive is main-actor state; hop to read it rather than
        // assuming this actor's execution context.
        let isActive = await MainActor.run { NSApp.isActive }
        guard !isActive else { return }

        // Provisional auth is requested here, on the first background
        // failure, not at app launch - see NotificationService's doc comment.
        await NotificationService.shared.requestAuthorizationIfNeeded()
        await NotificationService.shared.postBuildFailure(errorCount: errorCount, firstMessage: firstError.message)
    }

    private func handleProcessTermination(exitCode: Int32) async {
        Logger.shared.info("[HugoServer] Process terminated with exit code: \(exitCode)")

        let wasRunning = status.isRunning
        let previousSiteURL = siteRootURL

        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        outputPipe = nil
        errorPipe = nil

        if exitCode != 0 && wasRunning {
            // Unexpected termination - server crashed
            await updateStatus(.error(message: "Server crashed with exit code \(exitCode)"))

            // Attempt auto-restart if we have the site URL
            if let siteURL = previousSiteURL {
                Logger.shared.info("[HugoServer] Attempting auto-restart after crash...")
                crashRecoveryAttempts += 1

                // Only attempt recovery up to 3 times
                if crashRecoveryAttempts <= maxCrashRecoveryAttempts {
                    try? await Task.sleep(for: .seconds(2))
                    do {
                        try await start(siteURL: siteURL)
                        Logger.shared.info("[HugoServer] Auto-restart successful")
                        crashRecoveryAttempts = 0 // Reset on successful restart
                    } catch {
                        Logger.shared.error("[HugoServer] Auto-restart failed: \(error.localizedDescription)")
                    }
                } else {
                    Logger.shared.warning("[HugoServer] Max crash recovery attempts reached (\(maxCrashRecoveryAttempts))")
                    crashRecoveryAttempts = 0 // Reset for future attempts
                }
            }
        } else {
            await updateStatus(.stopped)
        }
    }

    // MARK: - Port Management

    private func isPortAvailable(_ port: Int) async -> Bool {
        // Try to create a socket on the port
        let socket = socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        defer { close(socket) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        return result == 0
    }

    private func findAvailablePort(startingFrom port: Int) async -> Int? {
        for offset in 0..<100 {
            let testPort = port + offset
            if await isPortAvailable(testPort) {
                return testPort
            }
        }
        return nil
    }

    // MARK: - State Updates

    private func updateStatus(_ newStatus: HugoServerStatus) async {
        status = newStatus
        await notifyStatusChange()
    }

    private func notifyStatusChange() async {
        let currentStatus = status
        for callback in statusChangeCallbacks.values {
            await callback(currentStatus)
        }
    }

    private func notifyBuildErrorsChange() async {
        let currentErrors = buildErrors
        for callback in buildErrorsChangeCallbacks.values {
            await callback(currentErrors)
        }
    }

    private func notifyOutputChange() async {
        let currentOutput = serverOutput
        for callback in outputChangeCallbacks.values {
            await callback(currentOutput)
        }
    }

    // MARK: - Cleanup

    /// Clean up resources when app terminates
    func cleanup() async {
        await stop()
    }
}

// MARK: - Hugo Server Errors

enum HugoServerError: LocalizedError {
    case hugoNotFound
    case portInUse(Int)
    case startFailed(String)
    case notRunning

    var errorDescription: String? {
        switch self {
        case .hugoNotFound:
            return "Hugo is not installed or not found in PATH. Please install Hugo first."
        case .portInUse(let port):
            return "Port \(port) is already in use. Please choose a different port."
        case .startFailed(let reason):
            return "Failed to start Hugo server: \(reason)"
        case .notRunning:
            return "Hugo server is not running"
        }
    }
}
