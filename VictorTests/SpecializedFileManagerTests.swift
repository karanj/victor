import XCTest
@testable import Victor

/// Tests for SpecializedFileManager - manages Hugo config, data files, templates, and archetypes
@MainActor
final class SpecializedFileManagerTests: XCTestCase {

    var tempDirectory: URL!
    var manager: SpecializedFileManager!

    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpecializedFileManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        manager = SpecializedFileManager()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - Hugo Config Tests

    func testLoadHugoConfigFromTOML() async throws {
        let configURL = tempDirectory.appendingPathComponent("hugo.toml")
        let content = """
        baseURL = "https://example.com"
        title = "Test Site"
        languageCode = "en-us"
        """
        try content.write(to: configURL, atomically: true, encoding: .utf8)

        try await manager.loadHugoConfig(from: configURL)

        XCTAssertNotNil(manager.hugoConfig)
        XCTAssertEqual(manager.hugoConfig?.baseURL, "https://example.com")
        XCTAssertEqual(manager.hugoConfig?.title, "Test Site")
    }

    func testHugoConfigIsNilBeforeLoad() {
        XCTAssertNil(manager.hugoConfig)
    }

    func testClearAllClearsHugoConfig() async throws {
        let configURL = tempDirectory.appendingPathComponent("hugo.toml")
        try "baseURL = \"https://example.com\"".write(to: configURL, atomically: true, encoding: .utf8)
        try await manager.loadHugoConfig(from: configURL)

        XCTAssertNotNil(manager.hugoConfig)

        manager.clearAll()

        XCTAssertNil(manager.hugoConfig)
    }

    // MARK: - Data File Tests

    func testLoadDataFileFromYAML() async throws {
        let dataURL = tempDirectory.appendingPathComponent("data.yaml")
        let content = """
        name: Test Data
        items:
          - one
          - two
        """
        try content.write(to: dataURL, atomically: true, encoding: .utf8)

        try await manager.loadDataFile(from: dataURL)

        let dataFile = manager.getDataFile(for: dataURL)
        XCTAssertNotNil(dataFile)
        XCTAssertEqual(dataFile?.fileName, "data.yaml")
    }

    func testGetDataFileReturnsNilForUnloaded() {
        let unknownURL = tempDirectory.appendingPathComponent("unknown.yaml")
        XCTAssertNil(manager.getDataFile(for: unknownURL))
    }

    func testDataFilePreservesUnsavedEdits() async throws {
        let dataURL = tempDirectory.appendingPathComponent("test.yaml")
        try "name: Original".write(to: dataURL, atomically: true, encoding: .utf8)

        try await manager.loadDataFile(from: dataURL)

        // Simulate edit by getting mutable reference
        let dataFile = manager.getDataFile(for: dataURL)
        XCTAssertNotNil(dataFile)

        // Reload should not overwrite (already loaded)
        try await manager.loadDataFile(from: dataURL)

        // Should still have the same instance
        XCTAssertTrue(dataFile === manager.getDataFile(for: dataURL))
    }

    // MARK: - Template Tests

    func testLoadTemplate() async throws {
        let templateURL = tempDirectory.appendingPathComponent("baseof.html")
        let content = """
        <!DOCTYPE html>
        <html>
        <body>{{ block "main" . }}{{ end }}</body>
        </html>
        """
        try content.write(to: templateURL, atomically: true, encoding: .utf8)

        try await manager.loadTemplate(from: templateURL)

        let template = manager.getTemplate(for: templateURL)
        XCTAssertNotNil(template)
        XCTAssertEqual(template?.fileName, "baseof.html")
    }

    func testGetTemplateReturnsNilForUnloaded() {
        let unknownURL = tempDirectory.appendingPathComponent("unknown.html")
        XCTAssertNil(manager.getTemplate(for: unknownURL))
    }

    // MARK: - Archetype Tests

    func testLoadArchetypeWithYAMLFrontmatter() async throws {
        let archetypeURL = tempDirectory.appendingPathComponent("default.md")
        let content = """
        ---
        title: "{{ replace .Name "-" " " | title }}"
        date: {{ .Date }}
        draft: true
        ---

        Content goes here.
        """
        try content.write(to: archetypeURL, atomically: true, encoding: .utf8)

        try await manager.loadArchetype(from: archetypeURL)

        let archetype = manager.getArchetype(for: archetypeURL)
        XCTAssertNotNil(archetype)
        XCTAssertEqual(archetype?.frontmatterFormat, .yaml)
    }

    func testLoadArchetypeWithTOMLFrontmatter() async throws {
        let archetypeURL = tempDirectory.appendingPathComponent("post.md")
        let content = """
        +++
        title = "{{ replace .Name \"-\" \" \" | title }}"
        date = {{ .Date }}
        +++

        Post content.
        """
        try content.write(to: archetypeURL, atomically: true, encoding: .utf8)

        try await manager.loadArchetype(from: archetypeURL)

        let archetype = manager.getArchetype(for: archetypeURL)
        XCTAssertNotNil(archetype)
        XCTAssertEqual(archetype?.frontmatterFormat, .toml)
    }

    func testGetArchetypeReturnsNilForUnloaded() {
        let unknownURL = tempDirectory.appendingPathComponent("unknown.md")
        XCTAssertNil(manager.getArchetype(for: unknownURL))
    }

    // MARK: - Clear All Tests

    func testClearAllClearsEverything() async throws {
        // Load one of each type
        let configURL = tempDirectory.appendingPathComponent("hugo.toml")
        try "baseURL = \"test\"".write(to: configURL, atomically: true, encoding: .utf8)
        try await manager.loadHugoConfig(from: configURL)

        let dataURL = tempDirectory.appendingPathComponent("data.yaml")
        try "name: test".write(to: dataURL, atomically: true, encoding: .utf8)
        try await manager.loadDataFile(from: dataURL)

        let templateURL = tempDirectory.appendingPathComponent("test.html")
        try "<html></html>".write(to: templateURL, atomically: true, encoding: .utf8)
        try await manager.loadTemplate(from: templateURL)

        let archetypeURL = tempDirectory.appendingPathComponent("default.md")
        try "---\ntitle: test\n---\n".write(to: archetypeURL, atomically: true, encoding: .utf8)
        try await manager.loadArchetype(from: archetypeURL)

        // Verify all loaded
        XCTAssertNotNil(manager.hugoConfig)
        XCTAssertNotNil(manager.getDataFile(for: dataURL))
        XCTAssertNotNil(manager.getTemplate(for: templateURL))
        XCTAssertNotNil(manager.getArchetype(for: archetypeURL))

        // Clear all
        manager.clearAll()

        // Verify all cleared
        XCTAssertNil(manager.hugoConfig)
        XCTAssertNil(manager.getDataFile(for: dataURL))
        XCTAssertNil(manager.getTemplate(for: templateURL))
        XCTAssertNil(manager.getArchetype(for: archetypeURL))
    }

    // MARK: - Has Unsaved Changes Tests

    func testHasUnsavedChangesInitiallyFalse() {
        XCTAssertFalse(manager.hasUnsavedChanges)
    }

    func testHasUnsavedChangesAfterHugoConfigEdit() async throws {
        let configURL = tempDirectory.appendingPathComponent("hugo.toml")
        try "baseURL = \"test\"".write(to: configURL, atomically: true, encoding: .utf8)
        try await manager.loadHugoConfig(from: configURL)

        XCTAssertFalse(manager.hasUnsavedChanges)

        // Simulate edit - HugoConfig tracks changes via rawContent
        manager.hugoConfig?.title = "Changed"
        manager.hugoConfig?.syncRawContentFromStructuredData()

        XCTAssertTrue(manager.hasUnsavedChanges)
    }
}
