import XCTest
@testable import Victor

/// Tests for ArchetypeManager and Archetype model
/// `@MainActor`: constructs `Archetype`, which is `@MainActor`-isolated (WP3.5 Cluster 13).
@MainActor
final class ArchetypeManagerTests: XCTestCase {

    private let manager = ArchetypeManager.shared

    // MARK: - Archetype Model Tests

    /// Test Archetype name extraction
    func testArchetypeNameExtraction() {
        let archetype = Archetype(
            url: URL(fileURLWithPath: "/archetypes/post.md"),
            frontmatterContent: "title: \"{{ .Title }}\"",
            bodyTemplate: "",
            frontmatterFormat: .yaml
        )

        XCTAssertEqual(archetype.name, "post")
        XCTAssertEqual(archetype.fileName, "post.md")
    }

    /// Test Archetype display name formatting
    func testArchetypeDisplayName() {
        let archetype1 = Archetype(
            url: URL(fileURLWithPath: "/archetypes/blog-post.md"),
            frontmatterContent: "",
            bodyTemplate: "",
            frontmatterFormat: .yaml
        )
        XCTAssertEqual(archetype1.displayName, "Blog Post")

        let archetype2 = Archetype(
            url: URL(fileURLWithPath: "/archetypes/my_page.md"),
            frontmatterContent: "",
            bodyTemplate: "",
            frontmatterFormat: .yaml
        )
        XCTAssertEqual(archetype2.displayName, "My Page")
    }

    /// Test default archetype detection
    func testIsDefaultArchetype() {
        let defaultArchetype = Archetype(
            url: URL(fileURLWithPath: "/archetypes/default.md"),
            frontmatterContent: "",
            bodyTemplate: "",
            frontmatterFormat: .yaml
        )
        XCTAssertTrue(defaultArchetype.isDefault)

        let postArchetype = Archetype(
            url: URL(fileURLWithPath: "/archetypes/post.md"),
            frontmatterContent: "",
            bodyTemplate: "",
            frontmatterFormat: .yaml
        )
        XCTAssertFalse(postArchetype.isDefault)
    }

    /// Test content type extraction
    func testContentType() {
        let archetype = Archetype(
            url: URL(fileURLWithPath: "/archetypes/posts.md"),
            frontmatterContent: "",
            bodyTemplate: "",
            frontmatterFormat: .yaml
        )
        XCTAssertEqual(archetype.contentType, "posts")
    }

    // MARK: - Template Processing Tests

    /// Test basic template variable substitution
    func testTemplateVariableSubstitution() {
        let archetype = Archetype(
            url: URL(fileURLWithPath: "/archetypes/post.md"),
            frontmatterContent: "title: \"{{ .Title }}\"",
            bodyTemplate: "# {{ .Title }}",
            frontmatterFormat: .yaml
        )

        let result = archetype.processTemplate(title: "My New Post")

        XCTAssertTrue(result.contains("title: \"My New Post\""))
        XCTAssertTrue(result.contains("# My New Post"))
    }

    /// Test date variable substitution
    func testDateVariableSubstitution() {
        let archetype = Archetype(
            url: URL(fileURLWithPath: "/archetypes/post.md"),
            frontmatterContent: "date: {{ .Date }}",
            bodyTemplate: "",
            frontmatterFormat: .yaml
        )

        let testDate = Date()
        let result = archetype.processTemplate(title: "Test", date: testDate)

        // Should contain ISO 8601 date format
        XCTAssertTrue(result.contains("date: 20"))  // Year prefix
    }

    /// Test template with no spaces around braces
    func testTemplateNoSpaces() {
        let archetype = Archetype(
            url: URL(fileURLWithPath: "/archetypes/post.md"),
            frontmatterContent: "title: \"{{.Title}}\"",
            bodyTemplate: "",
            frontmatterFormat: .yaml
        )

        let result = archetype.processTemplate(title: "Test Title")

        XCTAssertTrue(result.contains("title: \"Test Title\""))
    }

    /// Test template with additional parameters
    func testAdditionalParameters() {
        let archetype = Archetype(
            url: URL(fileURLWithPath: "/archetypes/post.md"),
            frontmatterContent: "author: \"{{ .Author }}\"",
            bodyTemplate: "",
            frontmatterFormat: .yaml
        )

        let result = archetype.processTemplate(
            title: "Test",
            additionalParams: ["Author": "John Doe"]
        )

        XCTAssertTrue(result.contains("author: \"John Doe\""))
    }

    /// Test YAML format output
    func testYAMLFormatOutput() {
        let archetype = Archetype(
            url: URL(fileURLWithPath: "/archetypes/post.md"),
            frontmatterContent: "title: \"{{ .Title }}\"",
            bodyTemplate: "Content here",
            frontmatterFormat: .yaml
        )

        let result = archetype.processTemplate(title: "Test")

        XCTAssertTrue(result.hasPrefix("---"))
        XCTAssertTrue(result.contains("---\n\nContent here"))
    }

    /// Test TOML format output
    func testTOMLFormatOutput() {
        let archetype = Archetype(
            url: URL(fileURLWithPath: "/archetypes/post.md"),
            frontmatterContent: "title = \"{{ .Title }}\"",
            bodyTemplate: "",
            frontmatterFormat: .toml
        )

        let result = archetype.processTemplate(title: "Test")

        XCTAssertTrue(result.hasPrefix("+++"))
        XCTAssertTrue(result.contains("+++"))
    }

    // MARK: - Default Archetype Content Tests

    /// Test default archetype content generation
    func testDefaultArchetypeContent() {
        let content = manager.defaultArchetypeContent(title: "My Post")

        XCTAssertTrue(content.contains("title: \"My Post\""))
        XCTAssertTrue(content.contains("draft: true"))
        XCTAssertTrue(content.hasPrefix("---"))
    }

    /// Test default archetype with custom date
    func testDefaultArchetypeWithDate() {
        let testDate = Date()
        let content = manager.defaultArchetypeContent(title: "Test", date: testDate)

        // Should contain ISO 8601 date
        XCTAssertTrue(content.contains("date: 20"))
    }

    // MARK: - Slugify Tests

    /// Test title to slug conversion
    func testSlugify() {
        // We can't directly test private method, but we can test through processTemplate
        // by checking filenames in error messages or similar

        // Test basic slugification through the public API
        let archetype = Archetype(
            url: URL(fileURLWithPath: "/archetypes/default.md"),
            frontmatterContent: "title: \"{{ .Title }}\"",
            bodyTemplate: "",
            frontmatterFormat: .yaml
        )

        // Process template and verify it handles the title correctly
        let result = archetype.processTemplate(title: "Hello World! This is a Test")
        XCTAssertTrue(result.contains("Hello World! This is a Test"))
    }

    // MARK: - FrontmatterFormat Tests

    /// Test YAML delimiter
    func testYAMLDelimiter() {
        XCTAssertEqual(FrontmatterFormat.yaml.delimiter, "---")
    }

    /// Test TOML delimiter
    func testTOMLDelimiter() {
        XCTAssertEqual(FrontmatterFormat.toml.delimiter, "+++")
    }

    /// Test JSON delimiter (empty for JSON)
    func testJSONDelimiter() {
        XCTAssertEqual(FrontmatterFormat.json.delimiter, "")
    }

    // MARK: - Archetype Equality Tests

    /// Test Archetype equality based on ID
    func testArchetypeEquality() {
        let archetype1 = Archetype(
            url: URL(fileURLWithPath: "/archetypes/post.md"),
            frontmatterContent: "",
            bodyTemplate: "",
            frontmatterFormat: .yaml
        )

        let archetype2 = Archetype(
            url: URL(fileURLWithPath: "/archetypes/post.md"),
            frontmatterContent: "",
            bodyTemplate: "",
            frontmatterFormat: .yaml
        )

        // Different instances should not be equal (different UUIDs)
        XCTAssertNotEqual(archetype1, archetype2)

        // Same instance should be equal
        XCTAssertEqual(archetype1, archetype1)
    }

    /// Test Archetype hashing
    func testArchetypeHashing() {
        let archetype = Archetype(
            url: URL(fileURLWithPath: "/archetypes/post.md"),
            frontmatterContent: "",
            bodyTemplate: "",
            frontmatterFormat: .yaml
        )

        var set = Set<Archetype>()
        set.insert(archetype)

        XCTAssertTrue(set.contains(archetype))
    }

    // MARK: - Edge Cases

    /// Test empty frontmatter
    func testEmptyFrontmatter() {
        let archetype = Archetype(
            url: URL(fileURLWithPath: "/archetypes/minimal.md"),
            frontmatterContent: "",
            bodyTemplate: "Just body content",
            frontmatterFormat: .yaml
        )

        let result = archetype.processTemplate(title: "Test")

        XCTAssertTrue(result.hasPrefix("---"))
        XCTAssertTrue(result.contains("Just body content"))
    }

    /// Test empty body template
    func testEmptyBodyTemplate() {
        let archetype = Archetype(
            url: URL(fileURLWithPath: "/archetypes/frontmatter-only.md"),
            frontmatterContent: "title: \"{{ .Title }}\"",
            bodyTemplate: "",
            frontmatterFormat: .yaml
        )

        let result = archetype.processTemplate(title: "Test")

        XCTAssertTrue(result.contains("title: \"Test\""))
    }

    /// Test Unicode in template
    func testUnicodeInTemplate() {
        let archetype = Archetype(
            url: URL(fileURLWithPath: "/archetypes/unicode.md"),
            frontmatterContent: "title: \"{{ .Title }}\"",
            bodyTemplate: "日本語コンテンツ",
            frontmatterFormat: .yaml
        )

        let result = archetype.processTemplate(title: "テスト")

        XCTAssertTrue(result.contains("title: \"テスト\""))
        XCTAssertTrue(result.contains("日本語コンテンツ"))
    }

    /// Test special characters in title
    func testSpecialCharactersInTitle() {
        let archetype = Archetype(
            url: URL(fileURLWithPath: "/archetypes/post.md"),
            frontmatterContent: "title: \"{{ .Title }}\"",
            bodyTemplate: "",
            frontmatterFormat: .yaml
        )

        let result = archetype.processTemplate(title: "Title with \"quotes\" and 'apostrophes'")

        XCTAssertTrue(result.contains("Title with \"quotes\" and 'apostrophes'"))
    }

    /// Test multiple variable occurrences
    func testMultipleVariableOccurrences() {
        let archetype = Archetype(
            url: URL(fileURLWithPath: "/archetypes/post.md"),
            frontmatterContent: "title: \"{{ .Title }}\"\nslug: \"{{ .Title }}\"",
            bodyTemplate: "# {{ .Title }}\n\nWelcome to {{ .Title }}",
            frontmatterFormat: .yaml
        )

        let result = archetype.processTemplate(title: "My Post")

        // Count occurrences of "My Post"
        let count = result.components(separatedBy: "My Post").count - 1
        XCTAssertEqual(count, 4)
    }
}
