import Foundation

// MARK: - LiveReload Event

/// A LiveReload event, delivered through `LiveReloadClient.events()`
/// (WP3.5 Cluster 9 / M2 - replaces the `onNavigate`/`onReload` callback pair).
enum LiveReloadEvent: Sendable {
    case navigate(String)
    case reload
}

// MARK: - URLSession Delegate for Certificate Validation

/// Delegate for handling WebSocket connection authentication challenges.
/// Provides certificate validation for secure connections (wss://).
final class LiveReloadSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {

    /// Localhost and loopback addresses that are trusted for local development
    private static let trustedLocalHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

    /// Resolve an authentication challenge and return the appropriate disposition.
    /// Exposed for testing purposes.
    /// - Parameter protectionSpace: The protection space describing the authentication challenge
    /// - Returns: The disposition to use for the challenge
    func resolveAuthChallenge(for protectionSpace: URLProtectionSpace) -> URLSession.AuthChallengeDisposition {
        // For non-server-trust challenges, use default handling
        guard protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            return .performDefaultHandling
        }

        // For localhost/loopback addresses, trust the server's certificate
        // This permits self-signed certificates commonly used in local development
        if Self.trustedLocalHosts.contains(protectionSpace.host),
           protectionSpace.serverTrust != nil {
            Logger.shared.debug("[LiveReload] Allowing local connection to \(protectionSpace.host)")
            return .useCredential
        }

        // For remote hosts, use default handling which enforces standard certificate validation
        return .performDefaultHandling
    }

}

// MARK: - URLSessionDelegate
//
// Moved to its own extension: the SDK's declared type for this optional
// requirement's completion handler is ambiguous between `@Sendable` and
// `@MainActor @Sendable` depending on how the conformance is imported
// (verified by toggling `@preconcurrency` on the conformance and rebuilding
// both ways - each variant "nearly matches" the other, and matching one
// breaks the other). `private` was tried too, but the compiler then reports
// this method *does* satisfy the protocol requirement and must be as
// accessible as the type - confirming the conformance is genuinely satisfied
// and this "nearly matches" warning is a false positive from the
// concurrency-attribute staging, not a real signature mismatch. Moving the
// method to an extension (the compiler's other suggested fix, alongside
// `private`) silences the warning without an accessibility conflict, and
// doesn't change dispatch: this is an `@objc` optional protocol requirement,
// so the ObjC runtime finds it by selector regardless of which extension
// declares it (WP3.5 Cluster 10).
extension LiveReloadSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let protectionSpace = challenge.protectionSpace
        let disposition = resolveAuthChallenge(for: protectionSpace)

        if disposition == .useCredential, let serverTrust = protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(disposition, nil)
        }
    }
}

// MARK: - LiveReload Client

/// Native WebSocket client for Hugo's LiveReload protocol
/// Handles reload and navigation messages from the Hugo server
actor LiveReloadClient {
    /// Shared singleton instance
    static let shared = LiveReloadClient()

    // MARK: - Types

    /// LiveReload message from Hugo server
    struct LiveReloadMessage: Codable {
        let command: String
        let path: String?
        let originalPath: String?
        let liveCSS: Bool?
        let liveImg: Bool?
        let overrideURL: Int?
        let protocols: [String]?
        let serverName: String?
    }

    /// Navigation prefix used by Hugo for --navigateToChanged
    private static let navigatePrefix = "__hugo_navigate"

    // MARK: - Properties

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var sessionDelegate: LiveReloadSessionDelegate?
    private var serverURL: URL?
    private var isConnected = false
    private var reconnectTask: Task<Void, Never>?

    /// Independent event streams (WP3.5 Cluster 9 / M2) - replaces the stored
    /// `onNavigate`/`onReload` `@MainActor` callbacks. `events()` is called by
    /// `ServerControlView`'s two call sites that used to call
    /// `connect(to:onNavigate:onReload:)`; the continuations are actor-level
    /// state decoupled from the WebSocket session lifecycle, so a reconnect
    /// (see `establishConnection()`) doesn't drop or duplicate a consumer's
    /// registration.
    private var eventContinuations: [UUID: AsyncStream<LiveReloadEvent>.Continuation] = [:]

    // MARK: - Public API

    /// New independent stream of LiveReload events (navigate/reload).
    func events() -> AsyncStream<LiveReloadEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: LiveReloadEvent.self)
        let id = UUID()
        eventContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeEventContinuation(id) }
        }
        return stream
    }

    private func removeEventContinuation(_ id: UUID) {
        eventContinuations.removeValue(forKey: id)
    }

    /// Connect to Hugo's LiveReload WebSocket
    /// - Parameter serverURL: The Hugo server base URL (e.g., http://localhost:1313)
    func connect(to serverURL: URL) {
        self.serverURL = serverURL

        establishConnection()
    }

    /// Disconnect from the LiveReload WebSocket
    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        sessionDelegate = nil
        isConnected = false
        Logger.shared.info("[LiveReload] Disconnected")
    }

    /// Check if currently connected
    func getIsConnected() -> Bool {
        isConnected
    }

    // MARK: - Connection Management

    private func establishConnection() {
        guard let serverURL = serverURL else { return }

        // Tear down any previous connection first - reconnect attempts would
        // otherwise leak a URLSession (and its delegate) per attempt
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil

        // Build WebSocket URL: ws://localhost:1313/livereload
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)
        components?.scheme = serverURL.scheme == "https" ? "wss" : "ws"
        components?.path = "/livereload"

        guard let wsURL = components?.url else {
            Logger.shared.error("[LiveReload] Failed to construct WebSocket URL")
            return
        }

        Logger.shared.info("[LiveReload] Connecting to \(wsURL.absoluteString)")

        // Create session with delegate for certificate validation
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        sessionDelegate = LiveReloadSessionDelegate()
        session = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)

        webSocketTask = session?.webSocketTask(with: wsURL)
        webSocketTask?.resume()

        // Send hello message (LiveReload protocol handshake)
        sendHello()

        // Start receiving messages
        receiveMessage()
    }

    private func sendHello() {
        // LiveReload protocol requires a hello handshake
        let hello: [String: Any] = [
            "command": "hello",
            "protocols": ["http://livereload.com/protocols/official-7"]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: hello),
              let string = String(data: data, encoding: .utf8) else {
            return
        }

        webSocketTask?.send(.string(string)) { [weak self] error in
            Task { [weak self] in
                if let error = error {
                    Logger.shared.error("[LiveReload] Failed to send hello: \(error.localizedDescription)")
                    await self?.scheduleReconnect()
                } else {
                    await self?.markConnected()
                }
            }
        }
    }

    private func markConnected() {
        isConnected = true
        Logger.shared.info("[LiveReload] Connected and listening for messages")
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { [weak self] in
                await self?.handleReceiveResult(result)
            }
        }
    }

    private func handleReceiveResult(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        switch result {
        case .success(let message):
            switch message {
            case .string(let text):
                handleMessage(text)
            case .data(let data):
                if let text = String(data: data, encoding: .utf8) {
                    handleMessage(text)
                }
            @unknown default:
                break
            }
            // Continue receiving
            receiveMessage()

        case .failure(let error):
            Logger.shared.error("[LiveReload] WebSocket error: \(error.localizedDescription)")
            isConnected = false
            scheduleReconnect()
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        do {
            let message = try JSONDecoder().decode(LiveReloadMessage.self, from: data)

            Logger.shared.debug("[LiveReload] Received: command=\(message.command), path=\(message.path ?? "nil")")

            switch message.command {
            case "reload":
                handleReload(message)
            case "hello":
                // Server acknowledged our hello
                if let serverName = message.serverName {
                    Logger.shared.info("[LiveReload] Handshake complete with server: \(serverName)")
                } else {
                    Logger.shared.info("[LiveReload] Handshake complete")
                }
            default:
                Logger.shared.debug("[LiveReload] Unknown command: \(message.command)")
            }
        } catch {
            // Log parsing errors for debugging
            Logger.shared.debug("[LiveReload] Could not parse message: \(error.localizedDescription)")
        }
    }

    /// Plain actor-local iteration - no `@MainActor` closures stored or passed
    /// anywhere (WP3.5 Cluster 9 / M2).
    private func broadcast(_ event: LiveReloadEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    /// Drives an event through the exact same fan-out path `handleReload`/
    /// `handleMessage` use, without needing a real WebSocket connection.
    /// Exposed for testing purposes (LiveReloadClientTests - proves `events()`
    /// delivers to every independently-obtained subscriber, not just that
    /// multiple streams can coexist).
    func broadcastForTesting(_ event: LiveReloadEvent) {
        broadcast(event)
    }

    private func handleReload(_ message: LiveReloadMessage) {
        guard let path = message.path else {
            Logger.shared.debug("[LiveReload] Reload message without path, refreshing")
            broadcast(.reload)
            return
        }

        // Check for navigation prefix
        if path.hasPrefix(Self.navigatePrefix) {
            // Extract the actual path after the prefix
            let navigatePath = String(path.dropFirst(Self.navigatePrefix.count))
            Logger.shared.info("[LiveReload] Navigate to: \(navigatePath)")

            broadcast(.navigate(navigatePath))
        } else {
            // Regular reload
            Logger.shared.debug("[LiveReload] Reload requested for path: \(path)")

            broadcast(.reload)
        }
    }

    // MARK: - Reconnection

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task {
            do {
                try await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                Logger.shared.info("[LiveReload] Attempting to reconnect...")
                establishConnection()
            } catch {
                // Task cancelled
            }
        }
    }
}
