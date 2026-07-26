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

// MARK: - Line Buffer

/// Accumulates raw pipe chunks and splits out complete lines. Chunk boundaries don't align
/// with line boundaries, so a partial line is held until its newline arrives.
///
/// `@unchecked Sendable` + NSLock: the readabilityHandler feeding `append` runs on a GCD
/// queue while `drain` can race it at EOF. All state access is inside the lock.
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()

    /// Append a chunk; returns any lines completed by it (newlines stripped,
    /// trailing CR removed so CRLF input behaves).
    func append(_ chunk: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        pending.append(chunk)
        var lines: [String] = []
        while let newlineIndex = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = pending.subdata(in: pending.startIndex..<newlineIndex)
            pending.removeSubrange(pending.startIndex...newlineIndex)
            lines.append(Self.decode(lineData))
        }
        return lines
    }

    /// Flush the trailing partial line (if any) at EOF.
    func drain() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !pending.isEmpty else { return nil }
        let line = Self.decode(pending)
        pending.removeAll()
        return line
    }

    private static func decode(_ data: Data) -> String {
        var line = String(decoding: data, as: UTF8.self)
        if line.hasSuffix("\r") {
            line.removeLast()
        }
        return line
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
    /// Non-private (victor-zw4): tests construct their own instance for
    /// isolation from the process-wide singleton. `init()` only reads
    /// UserDefaults (via `HugoServerConfig.fromUserDefaults()`'s `AppSettings`
    /// calls for the `config` property default) - no process/subprocess side
    /// effects, so plain construction is safe.
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

    /// Line-pumping tasks reading `outputPipe`/`errorPipe` via the
    /// `lines(from:)` readabilityHandler bridge (see setupOutputHandlers for
    /// why NOT `FileHandle.bytes.lines` - the stuck-on-starting fix).
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?

    /// Maximum lines of output to keep in memory
    private let maxOutputLines = 500

    /// Crash recovery tracking
    private var crashRecoveryAttempts = 0
    private let maxCrashRecoveryAttempts = 3

    // MARK: - Observation (AsyncStream)
    //
    // `AsyncStream` is single-consumer - two `for await` loops split elements rather than
    // both receiving them. Four places observe this service, and `ServerLogView` is in a
    // separate Window scene with no `SiteViewModel`, so one consumer that republishes
    // isn't available. Each `…Updates()` call makes its own stream+continuation pair;
    // the consuming Task's cancellation is the only deregistration mechanism.
    private var statusContinuations: [UUID: AsyncStream<HugoServerStatus>.Continuation] = [:]
    private var buildErrorContinuations: [UUID: AsyncStream<[HugoBuildError]>.Continuation] = [:]
    private var outputContinuations: [UUID: AsyncStream<[String]>.Continuation] = [:]

    init() {}

    // MARK: - Configuration

    /// Update server configuration
    func updateConfig(_ newConfig: HugoServerConfig) {
        config = newConfig
    }

    /// New independent stream of status changes. Replays the current value
    /// immediately so a late subscriber (e.g. Server Logs window opened after
    /// the server already started) doesn't have to separately fetch `status`
    /// first - this replay-on-subscribe behavior is new, not a port of
    /// something that existed before.
    func statusUpdates() -> AsyncStream<HugoServerStatus> {
        let (stream, continuation) = AsyncStream.makeStream(of: HugoServerStatus.self)
        let id = UUID()
        statusContinuations[id] = continuation
        continuation.yield(status)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeStatusContinuation(id) }
        }
        return stream
    }

    /// New independent stream of build-error changes. Replays the current value.
    func buildErrorUpdates() -> AsyncStream<[HugoBuildError]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [HugoBuildError].self)
        let id = UUID()
        buildErrorContinuations[id] = continuation
        continuation.yield(buildErrors)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeBuildErrorContinuation(id) }
        }
        return stream
    }

    /// New independent stream of server output changes. Replays the current value.
    func outputUpdates() -> AsyncStream<[String]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [String].self)
        let id = UUID()
        outputContinuations[id] = continuation
        continuation.yield(serverOutput)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeOutputContinuation(id) }
        }
        return stream
    }

    private func removeStatusContinuation(_ id: UUID) {
        statusContinuations.removeValue(forKey: id)
    }

    private func removeBuildErrorContinuation(_ id: UUID) {
        buildErrorContinuations.removeValue(forKey: id)
    }

    private func removeOutputContinuation(_ id: UUID) {
        outputContinuations.removeValue(forKey: id)
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
        notifyOutputChange()
        notifyBuildErrorsChange()

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

        // Stop pumping output before tearing down, so no stray reads fire
        // after the intentional stop (same ordering as the old
        // `readabilityHandler = nil` pair - WP3.5 Cluster 9 / M2).
        // `AsyncLineSequence` checks cancellation cooperatively between lines.
        stdoutTask?.cancel()
        stderrTask?.cancel()
        stdoutTask = nil
        stderrTask = nil

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

    /// Pump stdout/stderr via the `lines(from:)` readabilityHandler bridge. NOT
    /// `FileHandle.bytes.lines`: AsyncBytes funnels blocking `read(2)` through a shared
    /// per-process IO executor, so two concurrently-iterated pipes starve each other - the
    /// silent one parks a blocking read and the stdout reader is never serviced again.
    /// That left status stuck on `.starting` forever while the server ran fine.
    private func setupOutputHandlers(outputPipe: Pipe, errorPipe: Pipe) {
        stdoutTask = Task { [weak self] in
            for await line in Self.lines(from: outputPipe.fileHandleForReading) {
                guard let self else { return }
                await self.processLine(line, isError: false)
            }
        }
        stderrTask = Task { [weak self] in
            for await line in Self.lines(from: errorPipe.fileHandleForReading) {
                guard let self else { return }
                await self.processLine(line, isError: true)
            }
        }
    }

    /// Bridge a pipe's read end into an `AsyncStream` of lines. GCD invokes the handler only
    /// when data exists (or at EOF), so nothing blocks on a silent pipe. Empty
    /// `availableData` means EOF: flush the partial line, clear the handler, finish.
    ///
    /// `nonisolated static`: the handler runs on GCD's queue and must not hop through this
    /// actor - the point is that pumping never contends with actor work.
    nonisolated static func lines(from handle: FileHandle) -> AsyncStream<String> {
        AsyncStream { continuation in
            let buffer = LineBuffer()
            handle.readabilityHandler = { readHandle in
                let chunk = readHandle.availableData
                if chunk.isEmpty { // EOF
                    if let tail = buffer.drain() {
                        continuation.yield(tail)
                    }
                    readHandle.readabilityHandler = nil
                    continuation.finish()
                    return
                }
                for line in buffer.append(chunk) {
                    continuation.yield(line)
                }
            }
            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
            }
        }
    }

    private func processLine(_ line: String, isError: Bool) async {
        guard !line.isEmpty else { return }

        serverOutput.append(line)
        if serverOutput.count > maxOutputLines {
            serverOutput.removeFirst()
        }

        // Parse the line for status and errors
        await parseLine(line)

        notifyOutputChange()
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
            notifyBuildErrorsChange()
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
            notifyBuildErrorsChange()

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

        // Crash path (process died without stop() being called) - same
        // cancel pair as stop() (WP3.5 Cluster 9 / M2).
        stdoutTask?.cancel()
        stderrTask?.cancel()
        stdoutTask = nil
        stderrTask = nil
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
        notifyStatusChange()
    }

    private func notifyStatusChange() {
        let currentStatus = status
        for continuation in statusContinuations.values {
            continuation.yield(currentStatus)
        }
    }

    private func notifyBuildErrorsChange() {
        let currentErrors = buildErrors
        for continuation in buildErrorContinuations.values {
            continuation.yield(currentErrors)
        }
    }

    private func notifyOutputChange() {
        let currentOutput = serverOutput
        for continuation in outputContinuations.values {
            continuation.yield(currentOutput)
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
