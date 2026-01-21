import Foundation

// MARK: - URLSession Delegate for Certificate Validation

/// Delegate for handling WebSocket connection authentication challenges.
/// Provides certificate validation for secure connections (wss://).
final class LiveReloadSessionDelegate: NSObject, URLSessionDelegate {

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

        // For localhost/loopback addresses, allow the connection with default handling
        // This permits self-signed certificates commonly used in local development
        if Self.trustedLocalHosts.contains(protectionSpace.host) {
            Logger.shared.debug("[LiveReload] Allowing local connection to \(protectionSpace.host)")
            return .performDefaultHandling
        }

        // For remote hosts, use default handling which enforces standard certificate validation
        // This ensures proper TLS security for any non-local connections
        Logger.shared.debug("[LiveReload] Using default certificate validation for \(protectionSpace.host)")
        return .performDefaultHandling
    }

    // MARK: - URLSessionDelegate

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let disposition = resolveAuthChallenge(for: challenge.protectionSpace)
        completionHandler(disposition, nil)
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
    public struct LiveReloadMessage: Codable {
        public let command: String
        public let path: String?
        public let originalPath: String?
        public let liveCSS: Bool?
        public let liveImg: Bool?
        public let overrideURL: Int?
        public let protocols: [String]?
        public let serverName: String?
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

    /// Callback for navigation events
    private var onNavigate: (@MainActor (String) -> Void)?

    /// Callback for reload events (no navigation, just refresh)
    private var onReload: (@MainActor () -> Void)?

    // MARK: - Public API

    /// Connect to Hugo's LiveReload WebSocket
    /// - Parameters:
    ///   - serverURL: The Hugo server base URL (e.g., http://localhost:1313)
    ///   - onNavigate: Callback when Hugo sends a navigate command with the path to navigate to
    ///   - onReload: Callback when Hugo sends a reload command (refresh current page)
    func connect(
        to serverURL: URL,
        onNavigate: @escaping @MainActor (String) -> Void,
        onReload: @escaping @MainActor () -> Void
    ) {
        self.serverURL = serverURL
        self.onNavigate = onNavigate
        self.onReload = onReload

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

    private func handleReload(_ message: LiveReloadMessage) {
        guard let path = message.path else {
            Logger.shared.debug("[LiveReload] Reload message without path, refreshing")
            if let callback = onReload {
                Task { @MainActor in
                    callback()
                }
            }
            return
        }

        // Check for navigation prefix
        if path.hasPrefix(Self.navigatePrefix) {
            // Extract the actual path after the prefix
            let navigatePath = String(path.dropFirst(Self.navigatePrefix.count))
            Logger.shared.info("[LiveReload] Navigate to: \(navigatePath)")

            if let callback = onNavigate {
                Task { @MainActor in
                    callback(navigatePath)
                }
            }
        } else {
            // Regular reload
            Logger.shared.debug("[LiveReload] Reload requested for path: \(path)")

            if let callback = onReload {
                Task { @MainActor in
                    callback()
                }
            }
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
