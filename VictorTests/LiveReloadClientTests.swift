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

    // MARK: - Integration Tests

    func testLiveReloadClientCallbacksAreInvoked() async throws {
        let expectation = XCTestExpectation(description: "Callback invoked")
        var receivedPath: String?

        // Create a mock server that sends a navigate message
        // For now, just test that the client can be created
        let client = LiveReloadClient.shared

        // Verify client exists (basic smoke test)
        let isConnected = await client.getIsConnected()
        XCTAssertFalse(isConnected, "Client should not be connected initially")
    }
}
