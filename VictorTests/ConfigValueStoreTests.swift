import XCTest
import TOMLKit
@testable import Victor

/// Tests for `ConfigValueStore` — the sparse key-path store backing Config Editor v2.
/// See Docs/CONFIG-SCHEMA-SPEC.md §2.2 and §5 (Phase 1 test plan).
final class ConfigValueStoreTests: XCTestCase {

    // MARK: - Key-path get/set

    func testSetAndGetTopLevelValue() {
        let store = ConfigValueStore(root: [:])
        store.set("My Site", at: "title")
        XCTAssertEqual(store.value(at: "title") as? String, "My Site")
    }

    func testGetReturnsNilForMissingPath() {
        let store = ConfigValueStore(root: ["title": "My Site"])
        XCTAssertNil(store.value(at: "nonexistent"))
        XCTAssertNil(store.value(at: "markup.goldmark.renderer.unsafe"))
    }

    func testSetCreatesIntermediateDicts() {
        let store = ConfigValueStore(root: [:])
        store.set(true, at: "markup.goldmark.renderer.unsafe")

        XCTAssertEqual(store.value(at: "markup.goldmark.renderer.unsafe") as? Bool, true)
        let markup = store.subtree("markup")
        XCTAssertNotNil(markup)
        let goldmark = markup?["goldmark"] as? [String: Any]
        XCTAssertNotNil(goldmark)
        let renderer = goldmark?["renderer"] as? [String: Any]
        XCTAssertEqual(renderer?["unsafe"] as? Bool, true)
    }

    func testSetOverwritesExistingValueAtPath() {
        let store = ConfigValueStore(root: ["title": "Old"])
        store.set("New", at: "title")
        XCTAssertEqual(store.value(at: "title") as? String, "New")
    }

    func testRemovePrunesEmptyIntermediateDicts() {
        let store = ConfigValueStore(root: [:])
        store.set(true, at: "markup.goldmark.renderer.unsafe")
        store.remove(at: "markup.goldmark.renderer.unsafe")

        XCTAssertNil(store.value(at: "markup.goldmark.renderer.unsafe"))
        XCTAssertFalse(store.isPresent("markup"))
        XCTAssertFalse(store.isPresent("markup.goldmark"))
        XCTAssertFalse(store.isPresent("markup.goldmark.renderer"))
    }

    func testRemoveDoesNotPruneNonEmptySiblingDicts() {
        let store = ConfigValueStore(root: [:])
        store.set(true, at: "markup.goldmark.renderer.unsafe")
        store.set(true, at: "markup.goldmark.renderer.hardWraps")
        store.set("x", at: "markup.defaultMarkdownHandler")

        store.remove(at: "markup.goldmark.renderer.unsafe")

        // Sibling under the same now-pruned-candidate parent survives.
        XCTAssertEqual(store.value(at: "markup.goldmark.renderer.hardWraps") as? Bool, true)
        XCTAssertTrue(store.isPresent("markup.goldmark.renderer"))
        // Unrelated key elsewhere in the tree survives untouched.
        XCTAssertEqual(store.value(at: "markup.defaultMarkdownHandler") as? String, "x")
    }

    func testRemoveNonexistentPathIsNoop() {
        let store = ConfigValueStore(root: ["title": "My Site"])
        store.remove(at: "nonexistent")
        store.remove(at: "a.b.c")
        XCTAssertEqual(store.value(at: "title") as? String, "My Site")
    }

    func testRemoveTopLevelKeyDropsItEntirely() {
        let store = ConfigValueStore(root: ["title": "My Site", "buildDrafts": true])
        store.remove(at: "title")
        XCTAssertFalse(store.isPresent("title"))
        XCTAssertTrue(store.isPresent("buildDrafts"))
    }

    // MARK: - Presence semantics

    func testIsPresentTrueAfterSet() {
        let store = ConfigValueStore(root: [:])
        XCTAssertFalse(store.isPresent("buildDrafts"))
        store.set(true, at: "buildDrafts")
        XCTAssertTrue(store.isPresent("buildDrafts"))
    }

    func testIsPresentFalseAfterRemove() {
        let store = ConfigValueStore(root: ["buildDrafts": true])
        XCTAssertTrue(store.isPresent("buildDrafts"))
        store.remove(at: "buildDrafts")
        XCTAssertFalse(store.isPresent("buildDrafts"))
    }

    func testIsPresentFalseForKeyThatWasNeverSetEvenIfDefaultExists() {
        // ConfigValueStore has no notion of schema defaults; a path that was
        // never written is simply absent, regardless of any Hugo default
        // that a higher layer (ConfigSettingSpec) might apply.
        let store = ConfigValueStore(root: ["markup": ["goldmark": [:] as [String: Any]]])
        XCTAssertFalse(store.isPresent("markup.goldmark.renderer.unsafe"))
    }

    // MARK: - Lenient reads: bool

    func testBoolValueCoercions() {
        let store = ConfigValueStore(root: [
            "a": true,
            "b": false,
            "c": "true",
            "d": "false",
            "e": "TRUE",
            "f": 1,
            "g": 0,
            "h": "not-a-bool",
            "i": 2
        ])
        XCTAssertEqual(store.boolValue("a"), true)
        XCTAssertEqual(store.boolValue("b"), false)
        XCTAssertEqual(store.boolValue("c"), true)
        XCTAssertEqual(store.boolValue("d"), false)
        XCTAssertEqual(store.boolValue("e"), true)
        XCTAssertEqual(store.boolValue("f"), true)
        XCTAssertEqual(store.boolValue("g"), false)
        XCTAssertNil(store.boolValue("h"))
        XCTAssertNil(store.boolValue("i"))
        XCTAssertNil(store.boolValue("missing"))
    }

    // MARK: - Lenient reads: int

    func testIntValueCoercions() {
        let store = ConfigValueStore(root: [
            "a": 70,
            "b": 70.0,
            "c": 70.5,
            "d": "70",
            "e": "not-a-number"
        ])
        XCTAssertEqual(store.intValue("a"), 70)
        XCTAssertEqual(store.intValue("b"), 70)
        XCTAssertNil(store.intValue("c"))
        XCTAssertEqual(store.intValue("d"), 70)
        XCTAssertNil(store.intValue("e"))
        XCTAssertNil(store.intValue("missing"))
    }

    // MARK: - Lenient reads: double

    func testDoubleValueCoercions() {
        let store = ConfigValueStore(root: [
            "a": 0.5,
            "b": 1,
            "c": "0.5",
            "d": "not-a-number"
        ])
        XCTAssertEqual(store.doubleValue("a"), 0.5)
        XCTAssertEqual(store.doubleValue("b"), 1.0)
        XCTAssertEqual(store.doubleValue("c"), 0.5)
        XCTAssertNil(store.doubleValue("d"))
        XCTAssertNil(store.doubleValue("missing"))
    }

    // MARK: - Lenient reads: string

    func testStringValueCoercions() {
        let store = ConfigValueStore(root: [
            "a": "hello",
            "b": true,
            "c": false,
            "d": 42,
            "e": 0.5
        ])
        XCTAssertEqual(store.stringValue("a"), "hello")
        XCTAssertEqual(store.stringValue("b"), "true")
        XCTAssertEqual(store.stringValue("c"), "false")
        XCTAssertEqual(store.stringValue("d"), "42")
        XCTAssertEqual(store.stringValue("e"), "0.5")
        XCTAssertNil(store.stringValue("missing"))
    }

    // MARK: - Lenient reads: string array

    func testStringArrayValueCoercions() {
        let store = ConfigValueStore(root: [
            "a": ["x", "y", "z"],
            "b": ["x", "y"] as [Any],
            "c": "solo",
            "d": [1, 2, 3] as [Any]
        ])
        XCTAssertEqual(store.stringArrayValue("a"), ["x", "y", "z"])
        XCTAssertEqual(store.stringArrayValue("b"), ["x", "y"])
        XCTAssertEqual(store.stringArrayValue("c"), ["solo"])
        XCTAssertNil(store.stringArrayValue("d"))
        XCTAssertNil(store.stringArrayValue("missing"))
    }

    func testLenientReadsDoNotMutateVersion() {
        let store = ConfigValueStore(root: ["a": true, "b": 70, "c": "hello"])
        let versionBefore = store.version
        _ = store.boolValue("a")
        _ = store.intValue("b")
        _ = store.stringValue("c")
        _ = store.value(at: "a")
        _ = store.isPresent("a")
        _ = store.subtree("nonexistent")
        XCTAssertEqual(store.version, versionBefore)
    }

    // MARK: - [AnyHashable: Any] normalization at construction

    func testInitNormalizesAnyHashableDictionaries() {
        // Simulates what Yams.load returns for nested mappings.
        let innerAnyHashable: [AnyHashable: Any] = ["unsafe": true, "hardWraps": false]
        let root: [String: Any] = ["markup": ["goldmark": ["renderer": innerAnyHashable]]]

        let store = ConfigValueStore(root: root)

        XCTAssertEqual(store.boolValue("markup.goldmark.renderer.unsafe"), true)
        XCTAssertEqual(store.boolValue("markup.goldmark.renderer.hardWraps"), false)

        // The normalized subtree must be plain [String: Any], not [AnyHashable: Any].
        // Without normalization this cast fails and subtree(_:) returns nil —
        // that's the bug CLAUDE.md's "Yams Type Normalization" note documents.
        let renderer = store.subtree("markup.goldmark.renderer")
        XCTAssertNotNil(renderer)
        XCTAssertEqual(renderer?["unsafe"] as? Bool, true)
    }

    func testInitNormalizesAnyHashableDictionariesInsideArrays() {
        let item: [AnyHashable: Any] = ["name": "Home", "url": "/"]
        let root: [String: Any] = ["menu": ["main": [item]]]

        let store = ConfigValueStore(root: root)

        let mainMenu = store.value(at: "menu.main") as? [Any]
        XCTAssertEqual(mainMenu?.count, 1)
        let firstItem = mainMenu?.first as? [String: Any]
        XCTAssertEqual(firstItem?["name"] as? String, "Home")
    }

    // MARK: - snapshotRoot() round-trip through all three format writers

    private func sampleRoot() -> [String: Any] {
        return [
            "title": "My Site",
            "buildDrafts": true,
            "summaryLength": 70,
            "priority": 0.5,
            "tags": ["a", "b", "c"],
            "markup": [
                "goldmark": [
                    "renderer": [
                        "unsafe": false
                    ]
                ]
            ]
        ]
    }

    private func assertDictsEqual(
        _ lhs: [String: Any],
        _ rhs: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs as NSDictionary, rhs as NSDictionary, file: file, line: line)
    }

    func testSnapshotRoundTripThroughTOML() throws {
        let store = ConfigValueStore(root: sampleRoot())
        let snapshot = store.snapshotRoot()

        let serialized = TOMLHelper.serializeToTOML(snapshot)
        let table = try TOMLTable(string: serialized)
        let parsedBack = TOMLHelper.convertTOMLToDict(table)

        assertDictsEqual(snapshot, parsedBack)
    }

    func testSnapshotRoundTripThroughYAML() throws {
        let store = ConfigValueStore(root: sampleRoot())
        let snapshot = store.snapshotRoot()

        let serialized = try SerializationHelper.serializeToYAMLValidated(snapshot)
        let parsedBack = try SerializationHelper.parseYAML(serialized)

        assertDictsEqual(snapshot, parsedBack)
    }

    func testSnapshotRoundTripThroughJSON() throws {
        let store = ConfigValueStore(root: sampleRoot())
        let snapshot = store.snapshotRoot()

        let serialized = try SerializationHelper.serializeToJSON(snapshot)
        let parsedBack = try SerializationHelper.parseJSON(serialized)

        assertDictsEqual(snapshot, parsedBack)
    }

    // MARK: - replaceSubtree

    func testReplaceSubtreeSetsWholeDictionary() {
        let store = ConfigValueStore(root: ["params": ["author": "Old"]])
        store.replaceSubtree("params", with: ["author": "New", "description": "A site"])

        XCTAssertEqual(store.value(at: "params.author") as? String, "New")
        XCTAssertEqual(store.value(at: "params.description") as? String, "A site")
    }

    func testReplaceSubtreeCreatesPathIfAbsent() {
        let store = ConfigValueStore(root: [:])
        store.replaceSubtree("params", with: ["author": "New"])
        XCTAssertTrue(store.isPresent("params"))
        XCTAssertEqual(store.value(at: "params.author") as? String, "New")
    }

    // MARK: - version bumping

    func testSetBumpsVersion() {
        let store = ConfigValueStore(root: [:])
        let before = store.version
        store.set(true, at: "buildDrafts")
        XCTAssertGreaterThan(store.version, before)
    }

    func testRemoveBumpsVersion() {
        let store = ConfigValueStore(root: ["buildDrafts": true])
        let before = store.version
        store.remove(at: "buildDrafts")
        XCTAssertGreaterThan(store.version, before)
    }

    func testReplaceSubtreeBumpsVersion() {
        let store = ConfigValueStore(root: [:])
        let before = store.version
        store.replaceSubtree("params", with: ["author": "New"])
        XCTAssertGreaterThan(store.version, before)
    }

    // MARK: - Root key order preservation

    func testInitCapturesAllRootKeysInOrderedRootKeys() {
        let root: [String: Any] = ["title": "My Site", "buildDrafts": true, "baseURL": "https://example.com/"]
        let store = ConfigValueStore(root: root)

        XCTAssertEqual(Set(store.orderedRootKeys), Set(root.keys))
        XCTAssertEqual(store.orderedRootKeys.count, root.keys.count)
    }

    func testSetNewRootKeyAppendsToOrderedRootKeys() {
        let store = ConfigValueStore(root: ["title": "My Site"])
        let before = store.orderedRootKeys

        store.set(true, at: "buildDrafts")

        XCTAssertEqual(store.orderedRootKeys.count, before.count + 1)
        XCTAssertEqual(store.orderedRootKeys.last, "buildDrafts")
        // Existing keys keep their captured relative order.
        XCTAssertEqual(Array(store.orderedRootKeys.prefix(before.count)), before)
    }

    func testSetNewNestedKeyAppendsOnlyTopLevelSegmentOnce() {
        let store = ConfigValueStore(root: ["title": "My Site"])
        store.set(true, at: "markup.goldmark.renderer.unsafe")
        store.set(false, at: "markup.goldmark.renderer.hardWraps")

        XCTAssertEqual(store.orderedRootKeys.filter { $0 == "markup" }.count, 1)
        XCTAssertTrue(store.orderedRootKeys.contains("markup"))
    }

    func testSetExistingRootKeyDoesNotChangeOrderedRootKeys() {
        let store = ConfigValueStore(root: ["title": "My Site", "buildDrafts": true])
        let before = store.orderedRootKeys

        store.set("New Title", at: "title")

        XCTAssertEqual(store.orderedRootKeys, before)
    }

    func testRemoveRootKeyDropsItFromOrderedRootKeys() {
        let store = ConfigValueStore(root: ["title": "My Site", "buildDrafts": true, "baseURL": "https://example.com/"])
        XCTAssertTrue(store.orderedRootKeys.contains("buildDrafts"))

        store.remove(at: "buildDrafts")

        XCTAssertFalse(store.orderedRootKeys.contains("buildDrafts"))
        XCTAssertEqual(Set(store.orderedRootKeys), Set(["title", "baseURL"]))
    }

    func testRemoveNestedKeyThatPrunesRootDropsRootKeyFromOrder() {
        let store = ConfigValueStore(root: ["title": "My Site"])
        store.set(true, at: "markup.goldmark.renderer.unsafe")
        XCTAssertTrue(store.orderedRootKeys.contains("markup"))

        store.remove(at: "markup.goldmark.renderer.unsafe")

        XCTAssertFalse(store.orderedRootKeys.contains("markup"))
    }
}
