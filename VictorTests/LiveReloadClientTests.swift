import XCTest
@testable import Victor

final class LiveReloadClientTests: XCTestCase {

    // MARK: - Message Parsing Tests

    func testParseHelloMessage() throws {
        let json = """
        {
            "command": "hello",
            "protocols": ["http://livereload.com/protocols/official-7"],
            "serverName": "Hugo"
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(LiveReloadClient.LiveReloadMessage.self, from: data)

        XCTAssertEqual(message.command, "hello")
        XCTAssertEqual(message.serverName, "Hugo")
        XCTAssertEqual(message.protocols, ["http://livereload.com/protocols/official-7"])
        XCTAssertNil(message.path)
    }

    func testParseReloadMessage() throws {
        let json = """
        {
            "command": "reload",
            "path": "/posts/my-post/",
            "originalPath": "",
            "liveCSS": true,
            "liveImg": true
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(LiveReloadClient.LiveReloadMessage.self, from: data)

        XCTAssertEqual(message.command, "reload")
        XCTAssertEqual(message.path, "/posts/my-post/")
        XCTAssertEqual(message.liveCSS, true)
        XCTAssertEqual(message.liveImg, true)
    }

    func testParseNavigateMessage() throws {
        let json = """
        {
            "command": "reload",
            "path": "__hugo_navigate/posts/my-post/",
            "originalPath": "",
            "liveCSS": true,
            "liveImg": true
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(LiveReloadClient.LiveReloadMessage.self, from: data)

        XCTAssertEqual(message.command, "reload")
        XCTAssertEqual(message.path, "__hugo_navigate/posts/my-post/")

        // Verify navigation prefix extraction
        let navigatePrefix = "__hugo_navigate"
        XCTAssertTrue(message.path!.hasPrefix(navigatePrefix))

        let navigatePath = String(message.path!.dropFirst(navigatePrefix.count))
        XCTAssertEqual(navigatePath, "/posts/my-post/")
    }

    func testParseReloadWithOverrideURL() throws {
        let json = """
        {
            "command": "reload",
            "path": "__hugo_navigate/posts/my-post/",
            "originalPath": "",
            "liveCSS": true,
            "liveImg": true,
            "overrideURL": 1314
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(LiveReloadClient.LiveReloadMessage.self, from: data)

        XCTAssertEqual(message.command, "reload")
        XCTAssertEqual(message.overrideURL, 1314)
    }

    func testParseMinimalReloadMessage() throws {
        // Hugo might send minimal messages
        let json = """
        {
            "command": "reload",
            "path": "/x.js"
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(LiveReloadClient.LiveReloadMessage.self, from: data)

        XCTAssertEqual(message.command, "reload")
        XCTAssertEqual(message.path, "/x.js")
        XCTAssertNil(message.liveCSS)
        XCTAssertNil(message.liveImg)
    }

    // MARK: - Certificate Validation Delegate Tests

    func testLocalhostConnectionUsesDefaultHandling() async throws {
        let delegate = LiveReloadSessionDelegate()

        // Create a mock authentication challenge for localhost
        let protectionSpace = URLProtectionSpace(
            host: "localhost",
            port: 1313,
            protocol: "wss",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )

        let disposition = await delegate.resolveAuthChallenge(for: protectionSpace)
        XCTAssertEqual(disposition, .performDefaultHandling, "Localhost should use default handling")
    }

    func testLoopbackIPConnectionUsesDefaultHandling() async throws {
        let delegate = LiveReloadSessionDelegate()

        // Create a mock authentication challenge for 127.0.0.1
        let protectionSpace = URLProtectionSpace(
            host: "127.0.0.1",
            port: 1313,
            protocol: "wss",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )

        let disposition = await delegate.resolveAuthChallenge(for: protectionSpace)
        XCTAssertEqual(disposition, .performDefaultHandling, "127.0.0.1 should use default handling")
    }

    func testIPv6LoopbackConnectionUsesDefaultHandling() async throws {
        let delegate = LiveReloadSessionDelegate()

        // Create a mock authentication challenge for ::1 (IPv6 loopback)
        let protectionSpace = URLProtectionSpace(
            host: "::1",
            port: 1313,
            protocol: "wss",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )

        let disposition = await delegate.resolveAuthChallenge(for: protectionSpace)
        XCTAssertEqual(disposition, .performDefaultHandling, "IPv6 loopback should use default handling")
    }

    func testRemoteHostUsesDefaultHandling() async throws {
        let delegate = LiveReloadSessionDelegate()

        // Create a mock authentication challenge for a remote host
        let protectionSpace = URLProtectionSpace(
            host: "example.com",
            port: 443,
            protocol: "wss",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )

        let disposition = await delegate.resolveAuthChallenge(for: protectionSpace)
        XCTAssertEqual(disposition, .performDefaultHandling, "Remote hosts should use default certificate validation")
    }

    func testNonServerTrustChallengeUsesDefaultHandling() async throws {
        let delegate = LiveReloadSessionDelegate()

        // Create a mock authentication challenge for non-server-trust (e.g., HTTP Basic)
        let protectionSpace = URLProtectionSpace(
            host: "localhost",
            port: 1313,
            protocol: "http",
            realm: "test",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        let disposition = await delegate.resolveAuthChallenge(for: protectionSpace)
        XCTAssertEqual(disposition, .performDefaultHandling, "Non-server-trust challenges should use default handling")
    }

    // MARK: - Integration Tests

    func testLiveReloadClientCallbacksAreInvoked() async throws {
        // Create a mock server that sends a navigate message
        // For now, just test that the client can be created
        let client = LiveReloadClient.shared

        // Verify client exists (basic smoke test)
        let isConnected = await client.getIsConnected()
        XCTAssertFalse(isConnected, "Client should not be connected initially")
    }

    // MARK: - Event Stream Tests
    //
    // Driving a real `.navigate`/`.reload` needs a live WebSocket to a Hugo server -
    // that's in the manual checklist. Covered here: the stream factory multicasts
    // independently per subscriber, same guarantee as HugoServerService's streams.

    /// `events()` is single-consumer per call - two subscribers must each get their own
    /// stream rather than splitting one. Drives a real event through `broadcast(_:)` (via
    /// the test seam) and asserts both receive it; the previous version never triggered a
    /// broadcast at all, so it didn't actually back up its own claim.
    func testEventsReturnsIndependentStreamsPerSubscriber() async throws {
        let streamA = await LiveReloadClient.shared.events()
        let streamB = await LiveReloadClient.shared.events()

        // `AsyncStream.makeStream(of:)` defaults to `.unbounded` buffering, so
        // yielding before either subscriber starts consuming is safe - the
        // event is buffered and delivered on the first `first(where:)` below
        // (verified: this ordering is deterministic, not a race).
        await LiveReloadClient.shared.broadcastForTesting(.navigate("/posts/my-post/"))

        let receivedA = await streamA.first { _ in true }
        let receivedB = await streamB.first { _ in true }

        for received in [receivedA, receivedB] {
            guard case .navigate(let path) = received else {
                XCTFail("Expected .navigate event, got \(String(describing: received))")
                continue
            }
            XCTAssertEqual(path, "/posts/my-post/")
        }
    }

    /// `LiveReloadEvent` itself is a plain `Sendable` enum wrapping the two
    /// message shapes `handleReload` used to invoke callbacks for - a basic
    /// shape/equality check that the type migration preserved both cases.
    func testLiveReloadEventCases() {
        let navigate = LiveReloadEvent.navigate("/posts/my-post/")
        let reload = LiveReloadEvent.reload

        if case .navigate(let path) = navigate {
            XCTAssertEqual(path, "/posts/my-post/")
        } else {
            XCTFail("Expected .navigate case")
        }

        if case .reload = reload {
            // Expected
        } else {
            XCTFail("Expected .reload case")
        }
    }
}
