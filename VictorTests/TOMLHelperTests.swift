import XCTest
@testable import Victor

/// Tests for TOMLHelper TOML text serialization
final class TOMLHelperTests: XCTestCase {

    // MARK: - serializeToTOML

    func testSerializeSimpleValues() {
        let dict: [String: Any] = [
            "baseURL": "https://example.com",
            "buildDrafts": true,
            "summaryLength": 70,
            "weight": 3.14
        ]

        let result = TOMLHelper.serializeToTOML(dict)

        XCTAssertTrue(result.contains("baseURL = \"https://example.com\""))
        XCTAssertTrue(result.contains("buildDrafts = true"))
        XCTAssertTrue(result.contains("summaryLength = 70"))
        XCTAssertTrue(result.contains("weight = 3.14"))
    }

    func testSerializeNestedTable() {
        let dict: [String: Any] = [
            "title": "My Site",
            "params": [
                "author": "Test",
                "description": "A site"
            ] as [String: Any]
        ]

        let result = TOMLHelper.serializeToTOML(dict)

        XCTAssertTrue(result.contains("title = \"My Site\""))
        XCTAssertTrue(result.contains("[params]"))
        XCTAssertTrue(result.contains("author = \"Test\""))
        XCTAssertTrue(result.contains("description = \"A site\""))
    }

    func testSerializeArrayOfTables() {
        let dict: [String: Any] = [
            "menu": [
                "main": [
                    ["name": "Home", "weight": 1] as [String: Any],
                    ["name": "About", "weight": 2] as [String: Any]
                ]
            ] as [String: Any]
        ]

        let result = TOMLHelper.serializeToTOML(dict)

        XCTAssertTrue(result.contains("[[menu.main]]"))
        XCTAssertTrue(result.contains("name = \"Home\""))
        XCTAssertTrue(result.contains("name = \"About\""))
    }

    func testSerializeSimpleArray() {
        let dict: [String: Any] = [
            "tags": ["swift", "macos", "hugo"]
        ]

        let result = TOMLHelper.serializeToTOML(dict)

        XCTAssertTrue(result.contains("tags = [\"swift\", \"macos\", \"hugo\"]"))
    }

    func testSerializeStringEscaping() {
        let dict: [String: Any] = [
            "quote": "He said \"hello\"",
            "path": "C:\\Users\\test"
        ]

        let result = TOMLHelper.serializeToTOML(dict)

        XCTAssertTrue(result.contains("path = \"C:\\\\Users\\\\test\""))
        XCTAssertTrue(result.contains("quote = \"He said \\\"hello\\\"\""))
    }

    func testSerializeEmptyDict() {
        let dict: [String: Any] = [:]
        let result = TOMLHelper.serializeToTOML(dict)
        XCTAssertEqual(result, "\n")
    }

    func testSerializeNestedArrayOfTablesWithinArrayOfTables() {
        // HugoConfigParser's superset: nested [[a.b]] inside [[a]]
        let dict: [String: Any] = [
            "menu": [
                "main": [
                    [
                        "name": "Docs",
                        "children": [
                            ["name": "Getting Started"] as [String: Any],
                            ["name": "API Reference"] as [String: Any]
                        ]
                    ] as [String: Any]
                ]
            ] as [String: Any]
        ]

        let result = TOMLHelper.serializeToTOML(dict)

        XCTAssertTrue(result.contains("[[menu.main]]"))
        XCTAssertTrue(result.contains("[[menu.main.children]]"))
        XCTAssertTrue(result.contains("name = \"Getting Started\""))
        XCTAssertTrue(result.contains("name = \"API Reference\""))
    }

    func testSerializeSortedKeys() {
        let dict: [String: Any] = [
            "zebra": "last",
            "alpha": "first",
            "middle": "mid"
        ]

        let result = TOMLHelper.serializeToTOML(dict)
        let lines = result.components(separatedBy: "\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasPrefix("alpha"))
        XCTAssertTrue(lines[1].hasPrefix("middle"))
        XCTAssertTrue(lines[2].hasPrefix("zebra"))
    }

    func testSerializeBooleanArrayElements() {
        let dict: [String: Any] = [
            "flags": [true, false, true]
        ]

        let result = TOMLHelper.serializeToTOML(dict)
        XCTAssertTrue(result.contains("flags = [true, false, true]"))
    }

    func testSerializeIntArrayElements() {
        let dict: [String: Any] = [
            "ports": [80, 443, 8080]
        ]

        let result = TOMLHelper.serializeToTOML(dict)
        XCTAssertTrue(result.contains("ports = [80, 443, 8080]"))
    }

    func testSerializeNestedTableWithinArrayOfTables() {
        let dict: [String: Any] = [
            "items": [
                [
                    "name": "Item1",
                    "meta": ["key": "value"] as [String: Any]
                ] as [String: Any]
            ]
        ]

        let result = TOMLHelper.serializeToTOML(dict)

        XCTAssertTrue(result.contains("[[items]]"))
        XCTAssertTrue(result.contains("name = \"Item1\""))
        XCTAssertTrue(result.contains("[items.meta]"))
        XCTAssertTrue(result.contains("key = \"value\""))
    }

    func testSerializeTrailingNewline() {
        let dict: [String: Any] = ["key": "value"]
        let result = TOMLHelper.serializeToTOML(dict)
        XCTAssertTrue(result.hasSuffix("\n"))
    }
}
