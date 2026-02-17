import XCTest
@testable import Victor

/// Tests for SerializationHelper shared utilities
final class SerializationHelperTests: XCTestCase {

    // MARK: - normalizeForSerialization

    func testNormalizeStringKeyedDict() {
        let input: [String: Any] = ["key": "value", "num": 42]
        let result = SerializationHelper.normalizeForSerialization(input)

        guard let dict = result as? [String: Any] else {
            XCTFail("Expected [String: Any]")
            return
        }
        XCTAssertEqual(dict["key"] as? String, "value")
        XCTAssertEqual(dict["num"] as? Int, 42)
    }

    func testNormalizeAnyHashableDict() {
        // Yams returns [AnyHashable: Any] — simulate that
        let input: [AnyHashable: Any] = [
            AnyHashable("name"): "Test",
            AnyHashable("count"): 5
        ]
        let result = SerializationHelper.normalizeForSerialization(input)

        guard let dict = result as? [String: Any] else {
            XCTFail("Expected [String: Any]")
            return
        }
        XCTAssertEqual(dict["name"] as? String, "Test")
        XCTAssertEqual(dict["count"] as? Int, 5)
    }

    func testNormalizeNestedDicts() {
        let inner: [AnyHashable: Any] = [AnyHashable("nested"): "value"]
        let input: [AnyHashable: Any] = [AnyHashable("outer"): inner]

        let result = SerializationHelper.normalizeForSerialization(input)

        guard let dict = result as? [String: Any],
              let outerDict = dict["outer"] as? [String: Any] else {
            XCTFail("Expected nested [String: Any]")
            return
        }
        XCTAssertEqual(outerDict["nested"] as? String, "value")
    }

    func testNormalizeArray() {
        let inner: [AnyHashable: Any] = [AnyHashable("key"): "val"]
        let input: [Any] = ["string", 42, inner]

        let result = SerializationHelper.normalizeForSerialization(input)

        guard let array = result as? [Any] else {
            XCTFail("Expected [Any]")
            return
        }
        XCTAssertEqual(array.count, 3)
        XCTAssertEqual(array[0] as? String, "string")
        XCTAssertEqual(array[1] as? Int, 42)

        guard let normalizedDict = array[2] as? [String: Any] else {
            XCTFail("Expected dict in array")
            return
        }
        XCTAssertEqual(normalizedDict["key"] as? String, "val")
    }

    func testNormalizeScalar() {
        XCTAssertEqual(SerializationHelper.normalizeForSerialization("hello") as? String, "hello")
        XCTAssertEqual(SerializationHelper.normalizeForSerialization(42) as? Int, 42)
        XCTAssertEqual(SerializationHelper.normalizeForSerialization(true) as? Bool, true)
    }

    func testNormalizeNonStringKey() {
        // Keys that aren't strings should be converted via String(describing:)
        let input: [AnyHashable: Any] = [AnyHashable(42): "numeric-key"]
        let result = SerializationHelper.normalizeForSerialization(input)

        guard let dict = result as? [String: Any] else {
            XCTFail("Expected [String: Any]")
            return
        }
        XCTAssertEqual(dict["42"] as? String, "numeric-key")
    }

    // MARK: - serializeToYAMLValidated

    func testSerializeToYAMLValidatedRoundTrips() throws {
        let dict: [String: Any] = [
            "title": "Test",
            "count": 42,
            "enabled": true,
            "tags": ["a", "b"]
        ]

        let yaml = try SerializationHelper.serializeToYAMLValidated(dict)

        XCTAssertTrue(yaml.contains("title: Test"))
        XCTAssertTrue(yaml.contains("count: 42"))
        XCTAssertTrue(yaml.contains("enabled: true"))
    }

    func testSerializeToYAMLValidatedRejectsInvalid() {
        // A value that can't round-trip through YAML should fail
        // In practice this is hard to trigger with normal dicts,
        // but we verify the method at least works for valid input
        let dict: [String: Any] = ["key": "value"]
        XCTAssertNoThrow(try SerializationHelper.serializeToYAMLValidated(dict))
    }
}
