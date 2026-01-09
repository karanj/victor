import XCTest
@testable import Victor

/// Tests for DataFileParser parsing and serialization
final class DataFileParserTests: XCTestCase {

    private let parser = DataFileParser.shared

    // MARK: - YAML Parsing Tests

    /// Test parsing simple YAML dictionary
    func testParseYAMLDictionary() throws {
        let content = """
        name: "Test Site"
        description: "A test site"
        version: 1
        enabled: true
        """

        let data = try parser.parse(content: content, format: .yaml)

        guard let dict = data as? [String: Any] else {
            XCTFail("Expected dictionary")
            return
        }

        XCTAssertEqual(dict["name"] as? String, "Test Site")
        XCTAssertEqual(dict["description"] as? String, "A test site")
        XCTAssertEqual(dict["version"] as? Int, 1)
        XCTAssertEqual(dict["enabled"] as? Bool, true)
    }

    /// Test parsing YAML array
    func testParseYAMLArray() throws {
        let content = """
        - name: "Item 1"
          value: 100
        - name: "Item 2"
          value: 200
        """

        let data = try parser.parse(content: content, format: .yaml)

        guard let array = data as? [Any] else {
            XCTFail("Expected array")
            return
        }

        XCTAssertEqual(array.count, 2)

        if let first = array[0] as? [String: Any] {
            XCTAssertEqual(first["name"] as? String, "Item 1")
            XCTAssertEqual(first["value"] as? Int, 100)
        } else {
            XCTFail("Expected dictionary in array")
        }
    }

    /// Test parsing nested YAML structure
    func testParseNestedYAML() throws {
        let content = """
        site:
          title: "My Site"
          author:
            name: "John Doe"
            email: "john@example.com"
          tags:
            - swift
            - hugo
        """

        let data = try parser.parse(content: content, format: .yaml)

        guard let dict = data as? [String: Any],
              let site = dict["site"] as? [String: Any],
              let author = site["author"] as? [String: Any],
              let tags = site["tags"] as? [Any] else {
            XCTFail("Failed to parse nested structure")
            return
        }

        XCTAssertEqual(site["title"] as? String, "My Site")
        XCTAssertEqual(author["name"] as? String, "John Doe")
        XCTAssertEqual(tags.count, 2)
    }

    // MARK: - JSON Parsing Tests

    /// Test parsing simple JSON dictionary
    func testParseJSONDictionary() throws {
        let content = """
        {
          "name": "Test Site",
          "version": 2,
          "enabled": false
        }
        """

        let data = try parser.parse(content: content, format: .json)

        guard let dict = data as? [String: Any] else {
            XCTFail("Expected dictionary")
            return
        }

        XCTAssertEqual(dict["name"] as? String, "Test Site")
        XCTAssertEqual(dict["version"] as? Int, 2)
        XCTAssertEqual(dict["enabled"] as? Bool, false)
    }

    /// Test parsing JSON array
    func testParseJSONArray() throws {
        let content = """
        [
          {"id": 1, "title": "First"},
          {"id": 2, "title": "Second"}
        ]
        """

        let data = try parser.parse(content: content, format: .json)

        guard let array = data as? [Any] else {
            XCTFail("Expected array")
            return
        }

        XCTAssertEqual(array.count, 2)
    }

    // MARK: - TOML Parsing Tests

    /// Test parsing simple TOML
    func testParseTOML() throws {
        let content = """
        title = "Test Config"
        version = 3
        enabled = true
        """

        let data = try parser.parse(content: content, format: .toml)

        guard let dict = data as? [String: Any] else {
            XCTFail("Expected dictionary")
            return
        }

        XCTAssertEqual(dict["title"] as? String, "Test Config")
        XCTAssertEqual(dict["version"] as? Int, 3)
        XCTAssertEqual(dict["enabled"] as? Bool, true)
    }

    /// Test parsing TOML with nested tables
    func testParseTOMLNestedTables() throws {
        let content = """
        [database]
        host = "localhost"
        port = 5432

        [database.credentials]
        user = "admin"
        """

        let data = try parser.parse(content: content, format: .toml)

        guard let dict = data as? [String: Any],
              let database = dict["database"] as? [String: Any],
              let credentials = database["credentials"] as? [String: Any] else {
            XCTFail("Failed to parse nested tables")
            return
        }

        XCTAssertEqual(database["host"] as? String, "localhost")
        XCTAssertEqual(database["port"] as? Int, 5432)
        XCTAssertEqual(credentials["user"] as? String, "admin")
    }

    // MARK: - Serialization Tests

    /// Test YAML serialization round-trip
    func testYAMLSerializationRoundTrip() throws {
        let original: [String: Any] = [
            "name": "Test",
            "count": 42,
            "active": true,
            "tags": ["a", "b", "c"]
        ]

        let serialized = try parser.serialize(data: original, format: .yaml)
        let roundTrip = try parser.parse(content: serialized, format: .yaml)

        guard let result = roundTrip as? [String: Any] else {
            XCTFail("Expected dictionary")
            return
        }

        XCTAssertEqual(result["name"] as? String, "Test")
        XCTAssertEqual(result["count"] as? Int, 42)
        XCTAssertEqual(result["active"] as? Bool, true)
        XCTAssertEqual((result["tags"] as? [Any])?.count, 3)
    }

    /// Test JSON serialization round-trip
    func testJSONSerializationRoundTrip() throws {
        let original: [String: Any] = [
            "title": "JSON Test",
            "version": 1,
            "nested": ["key": "value"]
        ]

        let serialized = try parser.serialize(data: original, format: .json)
        let roundTrip = try parser.parse(content: serialized, format: .json)

        guard let result = roundTrip as? [String: Any] else {
            XCTFail("Expected dictionary")
            return
        }

        XCTAssertEqual(result["title"] as? String, "JSON Test")
        XCTAssertEqual(result["version"] as? Int, 1)

        if let nested = result["nested"] as? [String: Any] {
            XCTAssertEqual(nested["key"] as? String, "value")
        } else {
            XCTFail("Expected nested dictionary")
        }
    }

    /// Test TOML serialization round-trip
    func testTOMLSerializationRoundTrip() throws {
        let original: [String: Any] = [
            "name": "TOML Test",
            "port": 8080
        ]

        let serialized = try parser.serialize(data: original, format: .toml)
        let roundTrip = try parser.parse(content: serialized, format: .toml)

        guard let result = roundTrip as? [String: Any] else {
            XCTFail("Expected dictionary")
            return
        }

        XCTAssertEqual(result["name"] as? String, "TOML Test")
        XCTAssertEqual(result["port"] as? Int, 8080)
    }

    /// Test TOML cannot serialize array root
    func testTOMLRejectsArrayRoot() {
        let arrayData: [Any] = [
            ["name": "Item 1"],
            ["name": "Item 2"]
        ]

        XCTAssertThrowsError(try parser.serialize(data: arrayData, format: .toml)) { error in
            XCTAssertTrue(error is DataFileError)
        }
    }

    // MARK: - DataFormat Tests

    /// Test format detection from URL
    func testFormatDetectionFromURL() {
        XCTAssertEqual(DataFormat.from(url: URL(fileURLWithPath: "/test.yaml")), .yaml)
        XCTAssertEqual(DataFormat.from(url: URL(fileURLWithPath: "/test.yml")), .yaml)
        XCTAssertEqual(DataFormat.from(url: URL(fileURLWithPath: "/test.json")), .json)
        XCTAssertEqual(DataFormat.from(url: URL(fileURLWithPath: "/test.toml")), .toml)
        XCTAssertNil(DataFormat.from(url: URL(fileURLWithPath: "/test.txt")))
    }

    /// Test format extensions
    func testFormatExtensions() {
        XCTAssertEqual(DataFormat.yaml.extensions, ["yaml", "yml"])
        XCTAssertEqual(DataFormat.json.extensions, ["json"])
        XCTAssertEqual(DataFormat.toml.extensions, ["toml"])
    }

    // MARK: - DataFile Model Tests

    /// Test DataFile isArrayRoot detection
    func testDataFileIsArrayRoot() {
        let dictFile = DataFile(
            url: URL(fileURLWithPath: "/test.yaml"),
            format: .yaml,
            data: ["key": "value"],
            rawContent: "key: value"
        )
        XCTAssertFalse(dictFile.isArrayRoot)

        let arrayFile = DataFile(
            url: URL(fileURLWithPath: "/test.yaml"),
            format: .yaml,
            data: [["name": "item"]],
            rawContent: "- name: item"
        )
        XCTAssertTrue(arrayFile.isArrayRoot)
    }

    /// Test DataFile unsaved changes tracking
    func testDataFileUnsavedChanges() {
        let file = DataFile(
            url: URL(fileURLWithPath: "/test.yaml"),
            format: .yaml,
            data: ["key": "value"],
            rawContent: "key: value"
        )

        XCTAssertFalse(file.hasUnsavedChanges)

        file.updateRawContent("key: new value")
        XCTAssertTrue(file.hasUnsavedChanges)

        file.markAsSaved()
        XCTAssertFalse(file.hasUnsavedChanges)
    }

    /// Test DataFile accessors
    func testDataFileAccessors() {
        let dictFile = DataFile(
            url: URL(fileURLWithPath: "/test.yaml"),
            format: .yaml,
            data: ["key": "value"] as [String: Any],
            rawContent: "key: value"
        )

        XCTAssertNotNil(dictFile.dataDictionary)
        XCTAssertNil(dictFile.dataArray)

        let arrayFile = DataFile(
            url: URL(fileURLWithPath: "/test.yaml"),
            format: .yaml,
            data: [["name": "item"]] as [Any],
            rawContent: "- name: item"
        )

        XCTAssertNil(arrayFile.dataDictionary)
        XCTAssertNotNil(arrayFile.dataArray)
    }

    // MARK: - Error Handling Tests

    /// Test invalid YAML throws error
    func testInvalidYAMLThrows() {
        let content = "invalid: [unclosed"

        XCTAssertThrowsError(try parser.parse(content: content, format: .yaml))
    }

    /// Test invalid JSON throws error
    func testInvalidJSONThrows() {
        let content = "{invalid json"

        XCTAssertThrowsError(try parser.parse(content: content, format: .json))
    }

    /// Test invalid TOML throws error
    func testInvalidTOMLThrows() {
        let content = "invalid = \"unclosed"

        XCTAssertThrowsError(try parser.parse(content: content, format: .toml))
    }

    // MARK: - Edge Cases

    /// Test empty content
    func testEmptyYAML() throws {
        let content = ""

        // Empty YAML should return nil or throw
        XCTAssertThrowsError(try parser.parse(content: content, format: .yaml))
    }

    /// Test whitespace-only content
    func testWhitespaceOnlyYAML() throws {
        let content = "   \n\n   "

        XCTAssertThrowsError(try parser.parse(content: content, format: .yaml))
    }

    /// Test Unicode in data files
    func testUnicodeContent() throws {
        let content = """
        title: "日本語タイトル"
        description: "中文描述"
        tags:
          - 한국어
          - ελληνικά
        """

        let data = try parser.parse(content: content, format: .yaml)

        guard let dict = data as? [String: Any] else {
            XCTFail("Expected dictionary")
            return
        }

        XCTAssertEqual(dict["title"] as? String, "日本語タイトル")
        XCTAssertEqual(dict["description"] as? String, "中文描述")
    }
}
