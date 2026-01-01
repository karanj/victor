import XCTest
@testable import Victor

/// Tests for FrontmatterParser parsing and serialization
final class FrontmatterParserTests: XCTestCase {

    private let parser = FrontmatterParser.shared

    // MARK: - Format Detection Tests

    /// Test YAML format detection (---)
    func testDetectYAMLFormat() {
        let content = """
        ---
        title: "Test"
        ---
        Content here
        """

        let format = Frontmatter.detectFormat(from: content)
        XCTAssertEqual(format, .yaml)
    }

    /// Test TOML format detection (+++)
    func testDetectTOMLFormat() {
        let content = """
        +++
        title = "Test"
        +++
        Content here
        """

        let format = Frontmatter.detectFormat(from: content)
        XCTAssertEqual(format, .toml)
    }

    /// Test JSON format detection ({)
    func testDetectJSONFormat() {
        let content = """
        {
          "title": "Test"
        }
        Content here
        """

        let format = Frontmatter.detectFormat(from: content)
        XCTAssertEqual(format, .json)
    }

    /// Test no frontmatter detection
    func testDetectNoFormat() {
        let content = "Just some markdown content without frontmatter"

        let format = Frontmatter.detectFormat(from: content)
        XCTAssertNil(format)
    }

    /// Test format detection with leading whitespace
    func testDetectFormatWithWhitespace() {
        let content = """

        ---
        title: "Test"
        ---
        """

        let format = Frontmatter.detectFormat(from: content)
        XCTAssertEqual(format, .yaml)
    }

    // MARK: - YAML Parsing Tests

    /// Test parsing simple YAML frontmatter
    func testParseSimpleYAML() {
        let content = """
        ---
        title: "My Post"
        date: 2024-01-15
        draft: true
        ---
        # Content
        """

        let (frontmatter, markdown) = parser.parseContent(content)

        XCTAssertNotNil(frontmatter)
        XCTAssertEqual(frontmatter?.title, "My Post")
        XCTAssertEqual(frontmatter?.isDraft, true)
        XCTAssertNotNil(frontmatter?.date)
        XCTAssertEqual(frontmatter?.format, .yaml)
        XCTAssertTrue(markdown.contains("# Content"))
    }

    /// Test parsing YAML with arrays
    func testParseYAMLWithArrays() {
        let content = """
        ---
        title: "Tagged Post"
        tags:
          - swift
          - ios
          - macos
        categories:
          - programming
          - tutorials
        ---
        Content
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertNotNil(frontmatter)
        XCTAssertEqual(frontmatter?.tags, ["swift", "ios", "macos"])
        XCTAssertEqual(frontmatter?.categories, ["programming", "tutorials"])
    }

    /// Test parsing YAML with all essential fields
    func testParseYAMLEssentialFields() {
        let content = """
        ---
        title: "Complete Post"
        date: 2024-01-15
        draft: false
        description: "A comprehensive test post"
        tags:
          - test
        categories:
          - testing
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertEqual(frontmatter?.title, "Complete Post")
        XCTAssertEqual(frontmatter?.isDraft, false)
        XCTAssertEqual(frontmatter?.description, "A comprehensive test post")
        XCTAssertEqual(frontmatter?.tags, ["test"])
        XCTAssertEqual(frontmatter?.categories, ["testing"])
    }

    /// Test parsing YAML with URL fields
    func testParseYAMLURLFields() {
        let content = """
        ---
        title: "URL Test"
        slug: "custom-slug"
        url: "/custom/path/"
        aliases:
          - /old-url/
          - /another-old-url/
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertEqual(frontmatter?.slug, "custom-slug")
        XCTAssertEqual(frontmatter?.url, "/custom/path/")
        XCTAssertEqual(frontmatter?.aliases, ["/old-url/", "/another-old-url/"])
    }

    /// Test parsing YAML with SEO fields
    func testParseYAMLSEOFields() {
        let content = """
        ---
        title: "SEO Test"
        keywords:
          - swift
          - programming
        summary: "A brief summary"
        linkTitle: "Short Title"
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertEqual(frontmatter?.keywords, ["swift", "programming"])
        XCTAssertEqual(frontmatter?.summary, "A brief summary")
        XCTAssertEqual(frontmatter?.linkTitle, "Short Title")
    }

    /// Test parsing YAML with layout fields
    func testParseYAMLLayoutFields() {
        let content = """
        ---
        title: "Layout Test"
        type: "post"
        layout: "single"
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertEqual(frontmatter?.type, "post")
        XCTAssertEqual(frontmatter?.layout, "single")
    }

    /// Test parsing YAML with flag fields
    func testParseYAMLFlagFields() {
        let content = """
        ---
        title: "Flags Test"
        headless: true
        isCJKLanguage: true
        markup: "goldmark"
        translationKey: "about"
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertEqual(frontmatter?.headless, true)
        XCTAssertEqual(frontmatter?.isCJKLanguage, true)
        XCTAssertEqual(frontmatter?.markup, "goldmark")
        XCTAssertEqual(frontmatter?.translationKey, "about")
    }

    /// Test parsing YAML with weight
    func testParseYAMLWeight() {
        let content = """
        ---
        title: "Weighted"
        weight: 10
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertEqual(frontmatter?.weight, 10)
    }

    // MARK: - TOML Parsing Tests

    /// Test parsing simple TOML frontmatter
    func testParseSimpleTOML() throws {
        let content = """
        +++
        title = "TOML Post"
        date = "2024-01-15"
        draft = true
        +++
        # Content
        """

        let (frontmatter, markdown) = try parser.parseContentThrowing(content)

        XCTAssertNotNil(frontmatter)
        XCTAssertEqual(frontmatter?.title, "TOML Post")
        XCTAssertEqual(frontmatter?.isDraft, true)
        XCTAssertEqual(frontmatter?.format, .toml)
        XCTAssertTrue(markdown.contains("# Content"))
    }

    /// Test parsing TOML with arrays
    func testParseTOMLWithArrays() throws {
        let content = """
        +++
        title = "Tagged Post"
        tags = ["swift", "ios", "macos"]
        categories = ["programming"]
        +++
        """

        let (frontmatter, _) = try parser.parseContentThrowing(content)

        XCTAssertNotNil(frontmatter)
        XCTAssertEqual(frontmatter?.tags, ["swift", "ios", "macos"])
        XCTAssertEqual(frontmatter?.categories, ["programming"])
    }

    /// Test parsing TOML with all field types
    func testParseTOMLAllFields() throws {
        let content = """
        +++
        title = "Complete TOML"
        draft = false
        description = "A test post"
        slug = "custom-slug"
        weight = 5
        +++
        """

        let (frontmatter, _) = try parser.parseContentThrowing(content)

        XCTAssertNotNil(frontmatter)
        XCTAssertEqual(frontmatter?.title, "Complete TOML")
        XCTAssertEqual(frontmatter?.isDraft, false)
        XCTAssertEqual(frontmatter?.description, "A test post")
        XCTAssertEqual(frontmatter?.slug, "custom-slug")
        XCTAssertEqual(frontmatter?.weight, 5)
    }

    // MARK: - JSON Parsing Tests

    /// Test parsing simple JSON frontmatter
    func testParseSimpleJSON() {
        let content = """
        {
          "title": "JSON Post",
          "date": "2024-01-15",
          "draft": true
        }
        # Content
        """

        let (frontmatter, markdown) = parser.parseContent(content)

        XCTAssertNotNil(frontmatter)
        XCTAssertEqual(frontmatter?.title, "JSON Post")
        XCTAssertEqual(frontmatter?.isDraft, true)
        XCTAssertEqual(frontmatter?.format, .json)
        XCTAssertTrue(markdown.contains("# Content"))
    }

    /// Test parsing JSON with arrays
    func testParseJSONWithArrays() {
        let content = """
        {
          "title": "Tagged Post",
          "tags": ["swift", "ios"],
          "categories": ["programming"]
        }
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertEqual(frontmatter?.tags, ["swift", "ios"])
        XCTAssertEqual(frontmatter?.categories, ["programming"])
    }

    /// Test parsing JSON with nested structure
    func testParseJSONWithNested() {
        let content = """
        {
          "title": "Nested JSON",
          "params": {
            "author": "Test Author",
            "showToc": true
          }
        }
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertEqual(frontmatter?.title, "Nested JSON")
        XCTAssertEqual(frontmatter?.params["author"] as? String, "Test Author")
        XCTAssertEqual(frontmatter?.params["showToc"] as? Bool, true)
    }

    // MARK: - Menu Parsing Tests

    /// Test parsing simple menu string
    func testParseMenuString() {
        let content = """
        ---
        title: "Menu Test"
        menu: main
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertEqual(frontmatter?.menus.count, 1)
        XCTAssertEqual(frontmatter?.menus.first?.menuName, "main")
    }

    /// Test parsing menu array
    func testParseMenuArray() {
        let content = """
        ---
        title: "Multi Menu"
        menu:
          - main
          - footer
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertEqual(frontmatter?.menus.count, 2)
        XCTAssertTrue(frontmatter?.menuNames.contains("main") ?? false)
        XCTAssertTrue(frontmatter?.menuNames.contains("footer") ?? false)
    }

    /// Test parsing menu with configuration
    func testParseMenuWithConfig() {
        let content = """
        ---
        title: "Configured Menu"
        menu:
          main:
            weight: 10
            name: "Custom Name"
            parent: "parent-item"
            identifier: "about"
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertEqual(frontmatter?.menus.count, 1)
        let menu = frontmatter?.menus.first
        XCTAssertEqual(menu?.menuName, "main")
        XCTAssertEqual(menu?.weight, 10)
        XCTAssertEqual(menu?.name, "Custom Name")
        XCTAssertEqual(menu?.parent, "parent-item")
        XCTAssertEqual(menu?.identifier, "about")
    }

    // MARK: - Build Options Parsing Tests

    /// Test parsing build options
    func testParseBuildOptions() {
        let content = """
        ---
        title: "Build Test"
        build:
          list: never
          render: link
          publishResources: false
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertNotNil(frontmatter?.build)
        XCTAssertEqual(frontmatter?.build?.list, .never)
        XCTAssertEqual(frontmatter?.build?.render, .link)
        XCTAssertEqual(frontmatter?.build?.publishResources, false)
    }

    // MARK: - Sitemap Parsing Tests

    /// Test parsing sitemap configuration
    func testParseSitemapConfig() {
        let content = """
        ---
        title: "Sitemap Test"
        sitemap:
          changefreq: weekly
          priority: 0.8
          disable: false
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertNotNil(frontmatter?.sitemap)
        XCTAssertEqual(frontmatter?.sitemap?.changefreq, .weekly)
        XCTAssertEqual(frontmatter?.sitemap?.priority, 0.8)
        XCTAssertEqual(frontmatter?.sitemap?.disable, false)
    }

    // MARK: - Outputs Parsing Tests

    /// Test parsing outputs array
    func testParseOutputs() {
        let content = """
        ---
        title: "Outputs Test"
        outputs:
          - html
          - json
          - rss
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertEqual(frontmatter?.outputs, ["html", "json", "rss"])
    }

    // MARK: - Resources Parsing Tests

    /// Test parsing page resources
    func testParseResources() {
        let content = """
        ---
        title: "Resources Test"
        resources:
          - src: "images/*.jpg"
            name: "gallery"
            title: "Photo Gallery"
          - src: "documents/*.pdf"
            title: "PDF Documents"
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertEqual(frontmatter?.resources.count, 2)
        XCTAssertEqual(frontmatter?.resources[0].src, "images/*.jpg")
        XCTAssertEqual(frontmatter?.resources[0].name, "gallery")
        XCTAssertEqual(frontmatter?.resources[0].title, "Photo Gallery")
    }

    // MARK: - Cascade Parsing Tests

    /// Test parsing cascade configuration
    func testParseCascade() {
        let content = """
        ---
        title: "Cascade Test"
        cascade:
          - banner: "default-banner.jpg"
            target:
              path: "/blog/**"
              kind: page
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertEqual(frontmatter?.cascade.count, 1)
        XCTAssertEqual(frontmatter?.cascade[0].values["banner"] as? String, "default-banner.jpg")
        XCTAssertEqual(frontmatter?.cascade[0].target?.path, "/blog/**")
        XCTAssertEqual(frontmatter?.cascade[0].target?.kind, "page")
    }

    // MARK: - Custom Fields Tests

    /// Test that unknown fields are preserved in customFields
    func testCustomFieldsPreserved() {
        let content = """
        ---
        title: "Custom Fields"
        myCustomField: "custom value"
        anotherField: 42
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertEqual(frontmatter?.customFields["myCustomField"] as? String, "custom value")
        XCTAssertEqual(frontmatter?.customFields["anotherField"] as? Int, 42)
    }

    /// Test params section
    func testParamsSection() {
        let content = """
        ---
        title: "Params Test"
        params:
          author: "John Doe"
          showComments: true
          relatedPosts: 5
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertEqual(frontmatter?.params["author"] as? String, "John Doe")
        XCTAssertEqual(frontmatter?.params["showComments"] as? Bool, true)
        XCTAssertEqual(frontmatter?.params["relatedPosts"] as? Int, 5)
    }

    // MARK: - Date Parsing Tests

    /// Test various date formats
    func testDateFormats() {
        let formats = [
            "2024-01-15",
            "2024-01-15T10:30:00",
            "2024-01-15T10:30:00Z",
        ]

        for dateStr in formats {
            let content = """
            ---
            title: "Date Test"
            date: \(dateStr)
            ---
            """

            let (frontmatter, _) = parser.parseContent(content)
            XCTAssertNotNil(frontmatter?.date, "Failed to parse date: \(dateStr)")
        }
    }

    /// Test publishing date fields
    func testPublishingDates() {
        let content = """
        ---
        title: "Publishing Dates"
        date: 2024-01-15
        publishDate: 2024-01-20
        expiryDate: 2024-12-31
        lastmod: 2024-01-16
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertNotNil(frontmatter?.date)
        XCTAssertNotNil(frontmatter?.publishDate)
        XCTAssertNotNil(frontmatter?.expiryDate)
        XCTAssertNotNil(frontmatter?.lastmod)
    }

    // MARK: - Error Handling Tests

    /// Test that invalid YAML doesn't crash (non-throwing variant)
    func testInvalidYAMLDoesNotCrash() {
        let content = """
        ---
        title: [unclosed array
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)
        // Should return frontmatter with rawContent but parsing may fail gracefully
        XCTAssertNotNil(frontmatter)
    }

    /// Test that invalid YAML throws with throwing variant
    func testInvalidYAMLThrows() {
        let content = """
        ---
        title: [unclosed array
        ---
        """

        XCTAssertThrowsError(try parser.parseContentThrowing(content)) { error in
            XCTAssertTrue(error is FrontmatterError)
        }
    }

    /// Test that invalid TOML throws
    func testInvalidTOMLThrows() {
        let content = """
        +++
        title = "unclosed
        +++
        """

        XCTAssertThrowsError(try parser.parseContentThrowing(content)) { error in
            XCTAssertTrue(error is FrontmatterError)
        }
    }

    /// Test that invalid JSON throws
    func testInvalidJSONThrows() {
        let content = """
        {
          "title": missing quotes
        }
        """

        XCTAssertThrowsError(try parser.parseContentThrowing(content)) { error in
            XCTAssertTrue(error is FrontmatterError)
        }
    }

    // MARK: - Edge Cases Tests

    /// Test content with no frontmatter
    func testNoFrontmatter() {
        let content = "Just regular markdown content"

        let (frontmatter, markdown) = parser.parseContent(content)

        XCTAssertNil(frontmatter)
        XCTAssertEqual(markdown, content)
    }

    /// Test empty frontmatter
    func testEmptyYAMLFrontmatter() {
        let content = """
        ---
        ---
        Content here
        """

        let (frontmatter, markdown) = parser.parseContent(content)

        XCTAssertNotNil(frontmatter)
        XCTAssertTrue(markdown.contains("Content here"))
    }

    /// Test frontmatter with only whitespace content
    func testWhitespaceOnlyFrontmatter() {
        let content = """
        ---

        ---
        Content
        """

        let (frontmatter, _) = parser.parseContent(content)
        XCTAssertNotNil(frontmatter)
    }

    /// Test Unicode in frontmatter
    func testUnicodeFrontmatter() {
        let content = """
        ---
        title: "日本語タイトル"
        description: "Ελληνικά description"
        tags:
          - "中文"
          - "한국어"
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)

        XCTAssertEqual(frontmatter?.title, "日本語タイトル")
        XCTAssertEqual(frontmatter?.description, "Ελληνικά description")
        XCTAssertEqual(frontmatter?.tags?.count, 2)
    }

    /// Test special characters in values
    func testSpecialCharacters() {
        let content = """
        ---
        title: "Title with: colons"
        description: "Has 'quotes' and \\"escapes\\""
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)
        XCTAssertNotNil(frontmatter?.title)
        XCTAssertNotNil(frontmatter?.description)
    }

    /// Test multiline description in YAML
    func testMultilineYAML() {
        let content = """
        ---
        title: "Multiline Test"
        description: |
          This is a multiline
          description that spans
          multiple lines.
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)
        XCTAssertNotNil(frontmatter?.description)
        XCTAssertTrue(frontmatter?.description?.contains("multiline") ?? false)
    }

    // MARK: - Serialization Tests

    /// Test YAML serialization round-trip
    func testYAMLSerializationRoundTrip() {
        let content = """
        ---
        title: "Test Post"
        date: 2024-01-15
        draft: true
        tags:
          - swift
          - ios
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)
        XCTAssertNotNil(frontmatter)

        let serialized = parser.serializeFrontmatter(frontmatter!)

        // Parse again
        let (roundTrip, _) = parser.parseContent(serialized + "\nContent")

        XCTAssertEqual(roundTrip?.title, frontmatter?.title)
        XCTAssertEqual(roundTrip?.isDraft, frontmatter?.isDraft)
        XCTAssertEqual(roundTrip?.tags, frontmatter?.tags)
    }

    /// Test TOML serialization round-trip
    func testTOMLSerializationRoundTrip() {
        let content = """
        +++
        title = "TOML Test"
        draft = false
        tags = ["swift", "macos"]
        +++
        """

        let (frontmatter, _) = parser.parseContent(content)
        XCTAssertNotNil(frontmatter)

        let serialized = parser.serializeFrontmatter(frontmatter!)

        // Verify it starts with TOML delimiters
        XCTAssertTrue(serialized.hasPrefix("+++"))
        XCTAssertTrue(serialized.hasSuffix("+++"))

        // Parse again
        let (roundTrip, _) = parser.parseContent(serialized + "\nContent")

        XCTAssertEqual(roundTrip?.title, frontmatter?.title)
        XCTAssertEqual(roundTrip?.isDraft, frontmatter?.isDraft)
    }

    /// Test JSON serialization round-trip
    func testJSONSerializationRoundTrip() {
        let content = """
        {
          "title": "JSON Test",
          "draft": true,
          "tags": ["test"]
        }
        """

        let (frontmatter, _) = parser.parseContent(content)
        XCTAssertNotNil(frontmatter)

        let serialized = parser.serializeFrontmatter(frontmatter!)

        // Verify it's valid JSON
        XCTAssertTrue(serialized.hasPrefix("{"))
        XCTAssertTrue(serialized.hasSuffix("}"))

        // Parse again
        let (roundTrip, _) = parser.parseContent(serialized + "\nContent")

        XCTAssertEqual(roundTrip?.title, frontmatter?.title)
        XCTAssertEqual(roundTrip?.isDraft, frontmatter?.isDraft)
    }

    /// Test serialization preserves custom fields
    func testSerializationPreservesCustomFields() {
        let content = """
        ---
        title: "Custom Test"
        myCustomField: "preserved"
        anotherCustom: 123
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)
        let serialized = parser.serializeFrontmatter(frontmatter!)
        let (roundTrip, _) = parser.parseContent(serialized + "\nContent")

        XCTAssertEqual(roundTrip?.customFields["myCustomField"] as? String, "preserved")
        XCTAssertEqual(roundTrip?.customFields["anotherCustom"] as? Int, 123)
    }

    /// Test serialization preserves params
    func testSerializationPreservesParams() {
        let content = """
        ---
        title: "Params Test"
        params:
          author: "John"
          featured: true
        ---
        """

        let (frontmatter, _) = parser.parseContent(content)
        let serialized = parser.serializeFrontmatter(frontmatter!)
        let (roundTrip, _) = parser.parseContent(serialized + "\nContent")

        XCTAssertEqual(roundTrip?.params["author"] as? String, "John")
        XCTAssertEqual(roundTrip?.params["featured"] as? Bool, true)
    }

    /// Test throwing serialization
    func testThrowingSerializationYAML() throws {
        let frontmatter = Frontmatter(rawContent: "", format: .yaml)
        frontmatter.title = "Test"

        let serialized = try parser.serializeFrontmatterThrowing(frontmatter)
        XCTAssertTrue(serialized.hasPrefix("---"))
    }

    // MARK: - Markdown Extraction Tests

    /// Test markdown content is correctly extracted
    func testMarkdownExtraction() {
        let content = """
        ---
        title: "Test"
        ---

        # Heading

        Some paragraph content.

        - List item 1
        - List item 2
        """

        let (_, markdown) = parser.parseContent(content)

        XCTAssertTrue(markdown.contains("# Heading"))
        XCTAssertTrue(markdown.contains("Some paragraph content"))
        XCTAssertTrue(markdown.contains("- List item 1"))
    }

    /// Test JSON content extraction
    func testJSONMarkdownExtraction() {
        let content = """
        {
          "title": "JSON"
        }

        # After JSON

        Content after the JSON frontmatter.
        """

        let (frontmatter, markdown) = parser.parseContent(content)

        XCTAssertEqual(frontmatter?.title, "JSON")
        XCTAssertTrue(markdown.contains("# After JSON"))
    }

    // MARK: - Complex Field Serialization Tests

    /// Test menu serialization
    func testMenuSerialization() {
        let frontmatter = Frontmatter(rawContent: "", format: .yaml)
        frontmatter.title = "Menu Test"
        frontmatter.menus = [
            MenuEntry(menuName: "main", name: "Home", weight: 10),
            MenuEntry(menuName: "footer", weight: 20)
        ]

        let serialized = parser.serializeFrontmatter(frontmatter)
        let (roundTrip, _) = parser.parseContent(serialized + "\nContent")

        XCTAssertEqual(roundTrip?.menus.count, 2)
    }

    /// Test build options serialization
    func testBuildOptionsSerialization() {
        let frontmatter = Frontmatter(rawContent: "", format: .yaml)
        frontmatter.title = "Build Test"
        frontmatter.build = BuildOptions(list: .never, render: .link, publishResources: false)

        let serialized = parser.serializeFrontmatter(frontmatter)
        let (roundTrip, _) = parser.parseContent(serialized + "\nContent")

        XCTAssertEqual(roundTrip?.build?.list, .never)
        XCTAssertEqual(roundTrip?.build?.render, .link)
    }

    /// Test sitemap serialization
    func testSitemapSerialization() {
        let frontmatter = Frontmatter(rawContent: "", format: .yaml)
        frontmatter.title = "Sitemap Test"
        frontmatter.sitemap = SitemapConfig(changefreq: .monthly, priority: 0.5, disable: false)

        let serialized = parser.serializeFrontmatter(frontmatter)
        let (roundTrip, _) = parser.parseContent(serialized + "\nContent")

        XCTAssertEqual(roundTrip?.sitemap?.changefreq, .monthly)
        XCTAssertEqual(roundTrip?.sitemap?.priority, 0.5)
    }

    // MARK: - Frontmatter Convenience Methods Tests

    /// Test hasMenus property
    func testHasMenus() {
        let frontmatter = Frontmatter(rawContent: "", format: .yaml)
        XCTAssertFalse(frontmatter.hasMenus)

        frontmatter.menus = [MenuEntry(menuName: "main")]
        XCTAssertTrue(frontmatter.hasMenus)
    }

    /// Test hasParams property
    func testHasParams() {
        let frontmatter = Frontmatter(rawContent: "", format: .yaml)
        XCTAssertFalse(frontmatter.hasParams)

        frontmatter.params = ["key": "value"]
        XCTAssertTrue(frontmatter.hasParams)
    }

    /// Test hasCustomFields property
    func testHasCustomFields() {
        let frontmatter = Frontmatter(rawContent: "", format: .yaml)
        XCTAssertFalse(frontmatter.hasCustomFields)

        frontmatter.customFields = ["custom": "field"]
        XCTAssertTrue(frontmatter.hasCustomFields)
    }

    /// Test hasSitemap property
    func testHasSitemap() {
        let frontmatter = Frontmatter(rawContent: "", format: .yaml)
        XCTAssertFalse(frontmatter.hasSitemap)

        frontmatter.sitemap = SitemapConfig(changefreq: .weekly, priority: nil, disable: false)
        XCTAssertTrue(frontmatter.hasSitemap)
    }

    /// Test hasBuildOptions property
    func testHasBuildOptions() {
        let frontmatter = Frontmatter(rawContent: "", format: .yaml)
        XCTAssertFalse(frontmatter.hasBuildOptions)

        frontmatter.build = BuildOptions(list: .never, render: .always, publishResources: true)
        XCTAssertTrue(frontmatter.hasBuildOptions)
    }

    // MARK: - Format Delimiter Tests

    /// Test YAML delimiter
    func testYAMLDelimiter() {
        XCTAssertEqual(FrontmatterFormat.yaml.delimiter, "---")
    }

    /// Test TOML delimiter
    func testTOMLDelimiter() {
        XCTAssertEqual(FrontmatterFormat.toml.delimiter, "+++")
    }

    /// Test JSON delimiter (empty)
    func testJSONDelimiter() {
        XCTAssertEqual(FrontmatterFormat.json.delimiter, "")
    }
}
