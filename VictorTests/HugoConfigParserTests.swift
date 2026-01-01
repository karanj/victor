import XCTest
@testable import Victor

/// Tests for HugoConfigParser round-trip serialization
final class HugoConfigParserTests: XCTestCase {

    private let parser = HugoConfigParser.shared

    // MARK: - TOML Round-Trip Tests

    /// Test that simple TOML values survive a round-trip
    func testSimpleTOMLRoundTrip() throws {
        let input = """
        baseURL = "https://example.com/"
        title = "My Site"
        languageCode = "en-us"
        theme = "my-theme"
        """

        try assertTOMLRoundTrip(input)
    }

    /// Test that boolean values survive a round-trip
    func testBooleanTOMLRoundTrip() throws {
        let input = """
        baseURL = "https://example.com/"
        buildDrafts = true
        buildFuture = false
        enableRobotsTXT = true
        """

        try assertTOMLRoundTrip(input)
    }

    /// Test that integer values survive a round-trip
    func testIntegerTOMLRoundTrip() throws {
        let input = """
        baseURL = "https://example.com/"
        summaryLength = 70
        """

        try assertTOMLRoundTrip(input)
    }

    /// Test that simple tables survive a round-trip
    func testSimpleTableTOMLRoundTrip() throws {
        let input = """
        baseURL = "https://example.com/"

        [params]
        author = "John Doe"
        description = "A test site"
        """

        try assertTOMLRoundTrip(input)
    }

    /// Test that nested tables survive a round-trip
    func testNestedTableTOMLRoundTrip() throws {
        let input = """
        baseURL = "https://example.com/"

        [markup]
        [markup.goldmark]
        [markup.goldmark.renderer]
        unsafe = true
        """

        try assertTOMLRoundTrip(input)
    }

    /// Test that array of tables survives a round-trip
    /// This is the key test for the menu configuration
    func testArrayOfTablesTOMLRoundTrip() throws {
        let input = """
        baseURL = "https://example.com/"

        [menu]
        [[menu.main]]
        name = "Home"
        url = "/"
        weight = 10

        [[menu.main]]
        name = "About"
        url = "/about/"
        weight = 20
        """

        try assertTOMLRoundTrip(input)
    }

    /// Test a full Hugo config structure with nested tables and arrays of tables
    func testFullHugoConfigRoundTrip() throws {
        let input = """
        baseURL = "https://example.com/"
        languageCode = "en-us"
        title = "My Example Site"
        theme = "example-theme"

        [params]
        description = "An example Hugo site for testing"
        tagline = "Testing Made Easy"
        author = "Test Author"

        [menu]
        [[menu.main]]
        name = "Home"
        url = "/"
        weight = 10

        [[menu.main]]
        name = "About"
        url = "/about/"
        weight = 20

        [[menu.main]]
        name = "Blog"
        url = "/blog/"
        weight = 30

        [[menu.main]]
        name = "Recent Posts"
        url = "/blog/recent/"
        parent = "Blog"
        weight = 31

        [markup]
        [markup.goldmark]
        [markup.goldmark.renderer]
        unsafe = true
        """

        try assertTOMLRoundTrip(input)
    }

    // MARK: - YAML Round-Trip Tests

    /// Test that simple YAML values survive a round-trip
    func testSimpleYAMLRoundTrip() throws {
        let input = """
        baseURL: "https://example.com/"
        title: "My Site"
        languageCode: "en-us"
        theme: "my-theme"
        """

        try assertYAMLRoundTrip(input)
    }

    /// Test that boolean values survive a round-trip
    func testBooleanYAMLRoundTrip() throws {
        let input = """
        baseURL: "https://example.com/"
        buildDrafts: true
        buildFuture: false
        enableRobotsTXT: true
        """

        try assertYAMLRoundTrip(input)
    }

    /// Test that integer values survive a round-trip
    func testIntegerYAMLRoundTrip() throws {
        let input = """
        baseURL: "https://example.com/"
        summaryLength: 70
        """

        try assertYAMLRoundTrip(input)
    }

    /// Test that nested objects survive a round-trip
    func testNestedObjectYAMLRoundTrip() throws {
        let input = """
        baseURL: "https://example.com/"
        params:
          author: "John Doe"
          description: "A test site"
        """

        try assertYAMLRoundTrip(input)
    }

    /// Test that deeply nested objects survive a round-trip
    func testDeeplyNestedYAMLRoundTrip() throws {
        let input = """
        baseURL: "https://example.com/"
        markup:
          goldmark:
            renderer:
              unsafe: true
        """

        try assertYAMLRoundTrip(input)
    }

    /// Test that arrays of objects survive a round-trip (menu configuration)
    func testArrayOfObjectsYAMLRoundTrip() throws {
        let input = """
        baseURL: "https://example.com/"
        menu:
          main:
            - name: "Home"
              url: "/"
              weight: 10
            - name: "About"
              url: "/about/"
              weight: 20
        """

        try assertYAMLRoundTrip(input)
    }

    /// Test a full Hugo config structure in YAML
    func testFullHugoConfigYAMLRoundTrip() throws {
        let input = """
        baseURL: "https://example.com/"
        languageCode: "en-us"
        title: "My Example Site"
        theme: "example-theme"
        params:
          description: "An example Hugo site for testing"
          tagline: "Testing Made Easy"
          author: "Test Author"
        menu:
          main:
            - name: "Home"
              url: "/"
              weight: 10
            - name: "About"
              url: "/about/"
              weight: 20
            - name: "Blog"
              url: "/blog/"
              weight: 30
        markup:
          goldmark:
            renderer:
              unsafe: true
        """

        try assertYAMLRoundTrip(input)
    }

    // MARK: - JSON Round-Trip Tests

    /// Test that simple JSON values survive a round-trip
    func testSimpleJSONRoundTrip() throws {
        let input = """
        {
          "baseURL": "https://example.com/",
          "title": "My Site",
          "languageCode": "en-us",
          "theme": "my-theme"
        }
        """

        try assertJSONRoundTrip(input)
    }

    /// Test that boolean values survive a round-trip
    func testBooleanJSONRoundTrip() throws {
        let input = """
        {
          "baseURL": "https://example.com/",
          "buildDrafts": true,
          "buildFuture": false,
          "enableRobotsTXT": true
        }
        """

        try assertJSONRoundTrip(input)
    }

    /// Test that integer values survive a round-trip
    func testIntegerJSONRoundTrip() throws {
        let input = """
        {
          "baseURL": "https://example.com/",
          "summaryLength": 70
        }
        """

        try assertJSONRoundTrip(input)
    }

    /// Test that nested objects survive a round-trip
    func testNestedObjectJSONRoundTrip() throws {
        let input = """
        {
          "baseURL": "https://example.com/",
          "params": {
            "author": "John Doe",
            "description": "A test site"
          }
        }
        """

        try assertJSONRoundTrip(input)
    }

    /// Test that deeply nested objects survive a round-trip
    func testDeeplyNestedJSONRoundTrip() throws {
        let input = """
        {
          "baseURL": "https://example.com/",
          "markup": {
            "goldmark": {
              "renderer": {
                "unsafe": true
              }
            }
          }
        }
        """

        try assertJSONRoundTrip(input)
    }

    /// Test that arrays of objects survive a round-trip (menu configuration)
    func testArrayOfObjectsJSONRoundTrip() throws {
        let input = """
        {
          "baseURL": "https://example.com/",
          "menu": {
            "main": [
              {"name": "Home", "url": "/", "weight": 10},
              {"name": "About", "url": "/about/", "weight": 20}
            ]
          }
        }
        """

        try assertJSONRoundTrip(input)
    }

    /// Test a full Hugo config structure in JSON
    func testFullHugoConfigJSONRoundTrip() throws {
        let input = """
        {
          "baseURL": "https://example.com/",
          "languageCode": "en-us",
          "title": "My Example Site",
          "theme": "example-theme",
          "params": {
            "description": "An example Hugo site for testing",
            "tagline": "Testing Made Easy",
            "author": "Test Author"
          },
          "menu": {
            "main": [
              {"name": "Home", "url": "/", "weight": 10},
              {"name": "About", "url": "/about/", "weight": 20},
              {"name": "Blog", "url": "/blog/", "weight": 30}
            ]
          },
          "markup": {
            "goldmark": {
              "renderer": {
                "unsafe": true
              }
            }
          }
        }
        """

        try assertJSONRoundTrip(input)
    }

    // MARK: - HugoConfig Integration Tests

    /// Test that HugoConfig serialization produces valid TOML that Hugo can parse
    func testHugoConfigSerializationProducesValidTOML() throws {
        let input = """
        baseURL = "https://example.com/"
        languageCode = "en-us"
        title = "Test Site"
        theme = "my-theme"
        buildDrafts = true
        summaryLength = 100

        [params]
        author = "Test Author"
        description = "A test site"

        [menu]
        [[menu.main]]
        name = "Home"
        url = "/"
        weight = 10

        [[menu.main]]
        name = "About"
        url = "/about/"
        weight = 20
        """

        // Parse using public API
        let config = try parser.parseConfig(content: input, format: .toml)

        // Serialize through HugoConfigParser
        let serialized = try parser.serialize(config)

        // Verify the serialized TOML is valid by parsing it again
        let roundTripConfig = try parser.parseConfig(content: serialized, format: .toml)

        // Verify key fields are preserved
        XCTAssertEqual(roundTripConfig.baseURL, "https://example.com/")
        XCTAssertEqual(roundTripConfig.title, "Test Site")
        XCTAssertEqual(roundTripConfig.theme, "my-theme")
        XCTAssertEqual(roundTripConfig.buildDrafts, true)
        XCTAssertEqual(roundTripConfig.summaryLength, 100)

        // Verify nested params are preserved
        XCTAssertEqual(roundTripConfig.params["author"] as? String, "Test Author")
    }

    /// Test that HugoConfig serialization produces valid YAML
    func testHugoConfigSerializationProducesValidYAML() throws {
        let input = """
        baseURL: "https://example.com/"
        languageCode: "en-us"
        title: "Test Site"
        theme: "my-theme"
        buildDrafts: true
        summaryLength: 100
        params:
          author: "Test Author"
          description: "A test site"
        menu:
          main:
            - name: "Home"
              url: "/"
              weight: 10
            - name: "About"
              url: "/about/"
              weight: 20
        """

        // Parse using public API
        let config = try parser.parseConfig(content: input, format: .yaml)

        // Serialize through HugoConfigParser
        let serialized = try parser.serialize(config)

        // Verify the serialized YAML is valid by parsing it again
        let roundTripConfig = try parser.parseConfig(content: serialized, format: .yaml)

        // Verify key fields are preserved
        XCTAssertEqual(roundTripConfig.baseURL, "https://example.com/")
        XCTAssertEqual(roundTripConfig.title, "Test Site")
        XCTAssertEqual(roundTripConfig.theme, "my-theme")
        XCTAssertEqual(roundTripConfig.buildDrafts, true)
        XCTAssertEqual(roundTripConfig.summaryLength, 100)

        // Verify nested params are preserved
        XCTAssertEqual(roundTripConfig.params["author"] as? String, "Test Author")

        // Verify menu structure is preserved
        XCTAssertEqual(roundTripConfig.menus["main"]?.count, 2)
        XCTAssertEqual(roundTripConfig.menus["main"]?.first?.name, "Home")
    }

    /// Test that HugoConfig serialization produces valid JSON
    func testHugoConfigSerializationProducesValidJSON() throws {
        let input = """
        {
          "baseURL": "https://example.com/",
          "languageCode": "en-us",
          "title": "Test Site",
          "theme": "my-theme",
          "buildDrafts": true,
          "summaryLength": 100,
          "params": {
            "author": "Test Author",
            "description": "A test site"
          },
          "menu": {
            "main": [
              {"name": "Home", "url": "/", "weight": 10},
              {"name": "About", "url": "/about/", "weight": 20}
            ]
          }
        }
        """

        // Parse using public API
        let config = try parser.parseConfig(content: input, format: .json)

        // Serialize through HugoConfigParser
        let serialized = try parser.serialize(config)

        // Verify the serialized JSON is valid by parsing it again
        let roundTripConfig = try parser.parseConfig(content: serialized, format: .json)

        // Verify key fields are preserved
        XCTAssertEqual(roundTripConfig.baseURL, "https://example.com/")
        XCTAssertEqual(roundTripConfig.title, "Test Site")
        XCTAssertEqual(roundTripConfig.theme, "my-theme")
        XCTAssertEqual(roundTripConfig.buildDrafts, true)
        XCTAssertEqual(roundTripConfig.summaryLength, 100)

        // Verify nested params are preserved
        XCTAssertEqual(roundTripConfig.params["author"] as? String, "Test Author")

        // Verify menu structure is preserved
        XCTAssertEqual(roundTripConfig.menus["main"]?.count, 2)
        XCTAssertEqual(roundTripConfig.menus["main"]?.first?.name, "Home")
    }

    // MARK: - Error Handling Tests

    /// Test that invalid TOML throws an error
    func testInvalidTOMLThrowsError() {
        let invalidTOML = """
        baseURL = "unclosed string
        title = "Test"
        """

        XCTAssertThrowsError(try parser.parseConfig(content: invalidTOML, format: .toml))
    }

    /// Test that invalid YAML throws an error
    func testInvalidYAMLThrowsError() {
        let invalidYAML = """
        baseURL: "https://example.com/"
        title: [unclosed array
        """

        XCTAssertThrowsError(try parser.parseConfig(content: invalidYAML, format: .yaml))
    }

    /// Test that invalid JSON throws an error
    func testInvalidJSONThrowsError() {
        let invalidJSON = """
        {
          "baseURL": "https://example.com/",
          "title": missing quotes
        }
        """

        XCTAssertThrowsError(try parser.parseConfig(content: invalidJSON, format: .json))
    }

    /// Test that empty YAML input throws an error (returns nil, not a dictionary)
    func testEmptyYAMLThrowsError() {
        let emptyYAML = ""

        XCTAssertThrowsError(try parser.parseConfig(content: emptyYAML, format: .yaml))
    }

    /// Test that empty JSON throws an error
    func testEmptyJSONThrowsError() {
        let emptyJSON = ""

        XCTAssertThrowsError(try parser.parseConfig(content: emptyJSON, format: .json))
    }

    // MARK: - Edge Cases Tests

    /// Test minimal valid config (empty object)
    func testMinimalJSONConfig() throws {
        let input = "{}"
        let config = try parser.parseConfig(content: input, format: .json)

        // Empty config should have empty base URL and title
        XCTAssertTrue(config.baseURL.isEmpty)
        XCTAssertTrue(config.title.isEmpty)

        let serialized = try parser.serialize(config)
        let roundTrip = try parser.parseConfig(content: serialized, format: .json)
        XCTAssertTrue(roundTrip.baseURL.isEmpty)
    }

    /// Test minimal valid YAML config
    func testMinimalYAMLConfig() throws {
        let input = "baseURL: \"\""
        let config = try parser.parseConfig(content: input, format: .yaml)
        XCTAssertEqual(config.baseURL, "")
    }

    /// Test Unicode characters in values
    func testUnicodeCharactersRoundTrip() throws {
        let input = """
        {
          "baseURL": "https://example.com/",
          "title": "日本語タイトル",
          "params": {
            "author": "Müller",
            "tagline": "Ελληνικά",
            "emoji": "🚀✨🎉"
          }
        }
        """

        try assertJSONRoundTrip(input)
    }

    /// Test special characters that need escaping in TOML
    func testSpecialCharactersInTOML() throws {
        let input = """
        baseURL = "https://example.com/"
        title = "Title with \\"quotes\\" inside"
        """

        try assertTOMLRoundTrip(input)
    }

    /// Test special characters in YAML
    func testSpecialCharactersInYAML() throws {
        let input = """
        baseURL: "https://example.com/"
        title: "Title with: colons and #hashtags"
        description: "Line with 'single' and \\"double\\" quotes"
        """

        try assertYAMLRoundTrip(input)
    }

    /// Test backslash escaping in JSON
    func testBackslashEscapingInJSON() throws {
        let input = """
        {
          "baseURL": "https://example.com/",
          "title": "Path: C:\\\\Users\\\\test"
        }
        """

        try assertJSONRoundTrip(input)
    }

    /// Test very long string values
    func testLongStringValues() throws {
        let longString = String(repeating: "a", count: 10000)
        let input = """
        {
          "baseURL": "https://example.com/",
          "title": "\(longString)"
        }
        """

        let config = try parser.parseConfig(content: input, format: .json)
        XCTAssertEqual(config.title.count, 10000)

        try assertJSONRoundTrip(input)
    }

    /// Test multiline strings in YAML
    func testMultilineStringsInYAML() throws {
        let input = """
        baseURL: "https://example.com/"
        description: |
          This is a multiline
          description that spans
          multiple lines.
        """

        let config = try parser.parseConfig(content: input, format: .yaml)
        let description = config.customFields["description"] as? String
        XCTAssertNotNil(description)
        XCTAssertTrue(description?.contains("multiline") ?? false)
    }

    // MARK: - Hugo-Specific Features Tests

    /// Test theme as array (multiple themes)
    func testThemeAsArrayTOML() throws {
        let input = """
        baseURL = "https://example.com/"
        theme = ["base-theme", "child-theme"]
        """

        let config = try parser.parseConfig(content: input, format: .toml)
        XCTAssertEqual(config.theme, "base-theme, child-theme")
        XCTAssertTrue(config.themeIsArray)
    }

    /// Test theme as array in YAML
    func testThemeAsArrayYAML() throws {
        let input = """
        baseURL: "https://example.com/"
        theme:
          - base-theme
          - child-theme
          - override-theme
        """

        let config = try parser.parseConfig(content: input, format: .yaml)
        XCTAssertEqual(config.theme, "base-theme, child-theme, override-theme")
        XCTAssertTrue(config.themeIsArray)
    }

    /// Test multiple menus (main, footer, sidebar)
    func testMultipleMenus() throws {
        let input = """
        baseURL = "https://example.com/"

        [menu]
        [[menu.main]]
        name = "Home"
        url = "/"
        weight = 10

        [[menu.footer]]
        name = "Privacy"
        url = "/privacy/"
        weight = 10

        [[menu.footer]]
        name = "Terms"
        url = "/terms/"
        weight = 20

        [[menu.sidebar]]
        name = "Archives"
        url = "/archives/"
        weight = 10
        """

        let config = try parser.parseConfig(content: input, format: .toml)

        XCTAssertNotNil(config.menus["main"])
        XCTAssertNotNil(config.menus["footer"])
        XCTAssertNotNil(config.menus["sidebar"])
        XCTAssertEqual(config.menus["footer"]?.count, 2)
        XCTAssertEqual(config.menus.count, 3)
    }

    /// Test menu items with all optional fields
    func testMenuItemWithAllFields() throws {
        let input = """
        baseURL = "https://example.com/"

        [menu]
        [[menu.main]]
        name = "Services"
        url = "/services/"
        weight = 30
        identifier = "services"
        parent = ""

        [[menu.main]]
        name = "Consulting"
        pageRef = "/services/consulting"
        weight = 31
        identifier = "consulting"
        parent = "services"
        """

        let config = try parser.parseConfig(content: input, format: .toml)

        let menuItems = config.menus["main"]
        XCTAssertEqual(menuItems?.count, 2)

        let childItem = menuItems?.first { $0.name == "Consulting" }
        XCTAssertNotNil(childItem)
        XCTAssertEqual(childItem?.parent, "services")
        XCTAssertEqual(childItem?.identifier, "consulting")
        XCTAssertEqual(childItem?.pageRef, "/services/consulting")
    }

    /// Test custom taxonomies
    func testCustomTaxonomies() throws {
        let input = """
        baseURL = "https://example.com/"

        [taxonomies]
        tag = "tags"
        category = "categories"
        series = "series"
        author = "authors"
        """

        let config = try parser.parseConfig(content: input, format: .toml)

        XCTAssertEqual(config.taxonomies.count, 4)
        XCTAssertEqual(config.taxonomies["series"], "series")
        XCTAssertEqual(config.taxonomies["author"], "authors")
    }

    /// Test all build flags
    func testBuildFlags() throws {
        let input = """
        {
          "baseURL": "https://example.com/",
          "buildDrafts": true,
          "buildFuture": true,
          "buildExpired": true,
          "enableRobotsTXT": true
        }
        """

        let config = try parser.parseConfig(content: input, format: .json)

        XCTAssertTrue(config.buildDrafts)
        XCTAssertTrue(config.buildFuture)
        XCTAssertTrue(config.buildExpired)
        XCTAssertTrue(config.enableRobotsTXT)
    }

    /// Test timezone and language settings
    func testTimezoneAndLanguage() throws {
        let input = """
        baseURL: "https://example.com/"
        defaultContentLanguage: "de"
        timeZone: "Europe/Berlin"
        languageCode: "de-DE"
        """

        let config = try parser.parseConfig(content: input, format: .yaml)

        XCTAssertEqual(config.defaultContentLanguage, "de")
        XCTAssertEqual(config.timeZone, "Europe/Berlin")
        XCTAssertEqual(config.languageCode, "de-DE")
    }

    // MARK: - Type Handling Tests

    /// Test integer vs float distinction in JSON
    func testIntegerVsFloatJSON() throws {
        let input = """
        {
          "baseURL": "https://example.com/",
          "summaryLength": 70,
          "quality": 0.85
        }
        """

        let config = try parser.parseConfig(content: input, format: .json)
        XCTAssertEqual(config.summaryLength, 70)
        XCTAssertEqual(config.customFields["quality"] as? Double, 0.85)
    }

    /// Test integer vs float in TOML
    func testIntegerVsFloatTOML() throws {
        let input = """
        baseURL = "https://example.com/"
        summaryLength = 70
        quality = 0.85
        """

        let config = try parser.parseConfig(content: input, format: .toml)
        XCTAssertEqual(config.summaryLength, 70)
        XCTAssertEqual(config.customFields["quality"] as? Double, 0.85)
    }

    /// Test empty arrays
    func testEmptyArrays() throws {
        let input = """
        {
          "baseURL": "https://example.com/",
          "disableKinds": [],
          "theme": []
        }
        """

        let config = try parser.parseConfig(content: input, format: .json)
        let disableKinds = config.customFields["disableKinds"] as? [Any]
        XCTAssertNotNil(disableKinds)
        XCTAssertEqual(disableKinds?.count, 0)

        try assertJSONRoundTrip(input)
    }

    /// Test empty nested objects
    func testEmptyNestedObjects() throws {
        let input = """
        {
          "baseURL": "https://example.com/",
          "params": {},
          "menu": {}
        }
        """

        let config = try parser.parseConfig(content: input, format: .json)
        XCTAssertTrue(config.params.isEmpty)
        XCTAssertTrue(config.menus.isEmpty)

        try assertJSONRoundTrip(input)
    }

    /// Test arrays of strings (disableKinds)
    func testArrayOfStrings() throws {
        let input = """
        baseURL = "https://example.com/"
        disableKinds = ["taxonomy", "term", "RSS"]
        """

        let config = try parser.parseConfig(content: input, format: .toml)
        let disableKinds = config.customFields["disableKinds"] as? [String]
        XCTAssertEqual(disableKinds, ["taxonomy", "term", "RSS"])

        try assertTOMLRoundTrip(input)
    }

    /// Test negative integers
    func testNegativeIntegers() throws {
        let input = """
        {
          "baseURL": "https://example.com/",
          "offset": -10,
          "adjustment": -5
        }
        """

        let config = try parser.parseConfig(content: input, format: .json)
        XCTAssertEqual(config.customFields["offset"] as? Int, -10)

        try assertJSONRoundTrip(input)
    }

    /// Test boolean edge cases
    func testBooleanValues() throws {
        let input = """
        baseURL = "https://example.com/"
        enabled = true
        disabled = false
        """

        let config = try parser.parseConfig(content: input, format: .toml)
        XCTAssertEqual(config.customFields["enabled"] as? Bool, true)
        XCTAssertEqual(config.customFields["disabled"] as? Bool, false)

        try assertTOMLRoundTrip(input)
    }

    // MARK: - Custom Fields Preservation Tests

    /// Test that unknown top-level fields are preserved
    func testUnknownTopLevelFieldsPreserved() throws {
        let input = """
        baseURL = "https://example.com/"
        title = "Test Site"
        customSetting = "custom value"
        anotherUnknown = 42
        """

        let config = try parser.parseConfig(content: input, format: .toml)

        XCTAssertEqual(config.customFields["customSetting"] as? String, "custom value")
        XCTAssertEqual(config.customFields["anotherUnknown"] as? Int, 42)
    }

    /// Test that nested custom fields are preserved
    func testNestedCustomFieldsPreserved() throws {
        let input = """
        {
          "baseURL": "https://example.com/",
          "markup": {
            "goldmark": {
              "renderer": {
                "unsafe": true
              }
            },
            "highlight": {
              "style": "monokai"
            }
          },
          "outputs": {
            "home": ["HTML", "RSS", "JSON"]
          }
        }
        """

        let config = try parser.parseConfig(content: input, format: .json)

        // These should be in customFields since they're not known fields
        XCTAssertNotNil(config.customFields["markup"])
        XCTAssertNotNil(config.customFields["outputs"])

        let markup = config.customFields["markup"] as? [String: Any]
        let goldmark = markup?["goldmark"] as? [String: Any]
        let renderer = goldmark?["renderer"] as? [String: Any]
        XCTAssertEqual(renderer?["unsafe"] as? Bool, true)
    }

    /// Test that params nested fields are preserved
    func testParamsNestedFieldsPreserved() throws {
        let input = """
        baseURL: "https://example.com/"
        params:
          author: "Test Author"
          social:
            twitter: "@testuser"
            github: "testuser"
          features:
            comments: true
            analytics: false
        """

        let config = try parser.parseConfig(content: input, format: .yaml)

        XCTAssertEqual(config.params["author"] as? String, "Test Author")

        let social = config.params["social"] as? [String: Any]
        XCTAssertEqual(social?["twitter"] as? String, "@testuser")

        let features = config.params["features"] as? [String: Any]
        XCTAssertEqual(features?["comments"] as? Bool, true)
    }

    /// Test round-trip preserves custom fields through HugoConfig
    func testCustomFieldsRoundTripThroughHugoConfig() throws {
        let input = """
        baseURL = "https://example.com/"
        title = "Test Site"
        customSetting = "preserved"

        [imaging]
        quality = 85
        resampleFilter = "Lanczos"

        [outputs]
        home = ["HTML", "RSS", "JSON"]
        """

        let config = try parser.parseConfig(content: input, format: .toml)

        // Serialize and parse again
        let serialized = try parser.serialize(config)
        let roundTripConfig = try parser.parseConfig(content: serialized, format: .toml)

        XCTAssertEqual(roundTripConfig.customFields["customSetting"] as? String, "preserved")

        let imaging = roundTripConfig.customFields["imaging"] as? [String: Any]
        XCTAssertEqual(imaging?["quality"] as? Int, 85)
    }

    // MARK: - Format Detection Tests

    /// Test ConfigFormat detection from filename
    func testConfigFormatFromFilename() {
        XCTAssertEqual(ConfigFormat(filename: "hugo.toml"), .toml)
        XCTAssertEqual(ConfigFormat(filename: "config.toml"), .toml)
        XCTAssertEqual(ConfigFormat(filename: "hugo.yaml"), .yaml)
        XCTAssertEqual(ConfigFormat(filename: "config.yaml"), .yaml)
        XCTAssertEqual(ConfigFormat(filename: "hugo.yml"), .yaml)
        XCTAssertEqual(ConfigFormat(filename: "config.yml"), .yaml)
        XCTAssertEqual(ConfigFormat(filename: "hugo.json"), .json)
        XCTAssertEqual(ConfigFormat(filename: "config.json"), .json)
    }

    /// Test ConfigFormat case insensitivity
    func testConfigFormatCaseInsensitive() {
        XCTAssertEqual(ConfigFormat(filename: "HUGO.TOML"), .toml)
        XCTAssertEqual(ConfigFormat(filename: "Config.YAML"), .yaml)
        XCTAssertEqual(ConfigFormat(filename: "hugo.JSON"), .json)
    }

    /// Test ConfigFormat returns nil for unknown extensions
    func testConfigFormatUnknownExtension() {
        XCTAssertNil(ConfigFormat(filename: "config.txt"))
        XCTAssertNil(ConfigFormat(filename: "config.xml"))
        XCTAssertNil(ConfigFormat(filename: "config"))
        XCTAssertNil(ConfigFormat(filename: ""))
    }

    /// Test findConfigFile priority order
    func testFindConfigFilePriority() throws {
        // Create a temporary directory with multiple config files
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hugo-test-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create config.toml (lower priority)
        let configToml = tempDir.appendingPathComponent("config.toml")
        try "baseURL = \"https://example.com/\"".write(to: configToml, atomically: true, encoding: .utf8)

        // Verify config.toml is found when it's the only option
        var found = parser.findConfigFile(in: tempDir)
        XCTAssertEqual(found?.lastPathComponent, "config.toml")

        // Create hugo.toml (higher priority)
        let hugoToml = tempDir.appendingPathComponent("hugo.toml")
        try "baseURL = \"https://example.com/\"".write(to: hugoToml, atomically: true, encoding: .utf8)

        // Verify hugo.toml takes priority
        found = parser.findConfigFile(in: tempDir)
        XCTAssertEqual(found?.lastPathComponent, "hugo.toml")
    }

    /// Test findConfigFile returns nil when no config exists
    func testFindConfigFileReturnsNilWhenNoConfig() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hugo-empty-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let found = parser.findConfigFile(in: tempDir)
        XCTAssertNil(found)
    }

    /// Test findConfigFile finds YAML config
    func testFindConfigFileFindsYAML() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hugo-yaml-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let configYaml = tempDir.appendingPathComponent("hugo.yaml")
        try "baseURL: \"https://example.com/\"".write(to: configYaml, atomically: true, encoding: .utf8)

        let found = parser.findConfigFile(in: tempDir)
        XCTAssertEqual(found?.lastPathComponent, "hugo.yaml")
    }

    // MARK: - Helper Methods

    /// Assert that TOML content survives a parse -> serialize -> parse round-trip
    private func assertTOMLRoundTrip(_ input: String, file: StaticString = #file, line: UInt = #line) throws {
        let originalConfig = try parser.parseConfig(content: input, format: .toml)
        let serialized = try parser.serialize(originalConfig)
        let roundTripConfig = try parser.parseConfig(content: serialized, format: .toml)

        assertConfigsEqual(originalConfig, roundTripConfig, file: file, line: line)
    }

    /// Assert that YAML content survives a parse -> serialize -> parse round-trip
    private func assertYAMLRoundTrip(_ input: String, file: StaticString = #file, line: UInt = #line) throws {
        let originalConfig = try parser.parseConfig(content: input, format: .yaml)
        let serialized = try parser.serialize(originalConfig)
        let roundTripConfig = try parser.parseConfig(content: serialized, format: .yaml)

        assertConfigsEqual(originalConfig, roundTripConfig, file: file, line: line)
    }

    /// Assert that JSON content survives a parse -> serialize -> parse round-trip
    private func assertJSONRoundTrip(_ input: String, file: StaticString = #file, line: UInt = #line) throws {
        let originalConfig = try parser.parseConfig(content: input, format: .json)
        let serialized = try parser.serialize(originalConfig)
        let roundTripConfig = try parser.parseConfig(content: serialized, format: .json)

        assertConfigsEqual(originalConfig, roundTripConfig, file: file, line: line)
    }

    /// Compare two HugoConfig objects for equality
    private func assertConfigsEqual(_ lhs: HugoConfig, _ rhs: HugoConfig, file: StaticString = #file, line: UInt = #line) {
        // Compare known fields
        XCTAssertEqual(lhs.baseURL, rhs.baseURL, "baseURL mismatch", file: file, line: line)
        XCTAssertEqual(lhs.title, rhs.title, "title mismatch", file: file, line: line)
        XCTAssertEqual(lhs.languageCode, rhs.languageCode, "languageCode mismatch", file: file, line: line)
        // Theme: treat nil and empty string as equivalent (empty array becomes "")
        XCTAssertTrue(
            optionalStringsEquivalent(lhs.theme, rhs.theme),
            "theme mismatch: \(String(describing: lhs.theme)) vs \(String(describing: rhs.theme))",
            file: file,
            line: line
        )
        XCTAssertEqual(lhs.buildDrafts, rhs.buildDrafts, "buildDrafts mismatch", file: file, line: line)
        XCTAssertEqual(lhs.buildFuture, rhs.buildFuture, "buildFuture mismatch", file: file, line: line)
        XCTAssertEqual(lhs.buildExpired, rhs.buildExpired, "buildExpired mismatch", file: file, line: line)
        XCTAssertEqual(lhs.enableRobotsTXT, rhs.enableRobotsTXT, "enableRobotsTXT mismatch", file: file, line: line)
        XCTAssertEqual(lhs.summaryLength, rhs.summaryLength, "summaryLength mismatch", file: file, line: line)
        XCTAssertEqual(lhs.defaultContentLanguage, rhs.defaultContentLanguage, "defaultContentLanguage mismatch", file: file, line: line)
        XCTAssertEqual(lhs.timeZone, rhs.timeZone, "timeZone mismatch", file: file, line: line)
        XCTAssertEqual(lhs.copyright, rhs.copyright, "copyright mismatch", file: file, line: line)

        // Compare params
        XCTAssertTrue(
            dictionariesEqual(lhs.params, rhs.params),
            "params mismatch: \(lhs.params) vs \(rhs.params)",
            file: file,
            line: line
        )

        // Compare custom fields
        XCTAssertTrue(
            dictionariesEqual(lhs.customFields, rhs.customFields),
            "customFields mismatch: \(lhs.customFields) vs \(rhs.customFields)",
            file: file,
            line: line
        )

        // Compare menus
        XCTAssertEqual(lhs.menus.count, rhs.menus.count, "menus count mismatch", file: file, line: line)
        for (menuName, lhsItems) in lhs.menus {
            let rhsItems = rhs.menus[menuName]
            XCTAssertEqual(lhsItems.count, rhsItems?.count ?? 0, "menu \(menuName) item count mismatch", file: file, line: line)
        }
    }

    /// Deep compare two dictionaries
    private func dictionariesEqual(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        guard lhs.keys.count == rhs.keys.count else { return false }

        for (key, lhsValue) in lhs {
            guard let rhsValue = rhs[key] else { return false }

            if !valuesEqual(lhsValue, rhsValue) {
                return false
            }
        }

        return true
    }

    /// Deep compare two values
    private func valuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        switch (lhs, rhs) {
        case let (l as String, r as String):
            return l == r
        case let (l as Int, r as Int):
            return l == r
        case let (l as Double, r as Double):
            return l == r
        case let (l as Bool, r as Bool):
            return l == r
        case let (l as [String: Any], r as [String: Any]):
            return dictionariesEqual(l, r)
        case let (l as [Any], r as [Any]):
            guard l.count == r.count else { return false }
            for (lItem, rItem) in zip(l, r) {
                if !valuesEqual(lItem, rItem) {
                    return false
                }
            }
            return true
        default:
            // Try string comparison as fallback
            return String(describing: lhs) == String(describing: rhs)
        }
    }

    /// Compare optional strings, treating nil and empty string as equivalent
    private func optionalStringsEquivalent(_ lhs: String?, _ rhs: String?) -> Bool {
        let lhsEmpty = lhs == nil || lhs?.isEmpty == true
        let rhsEmpty = rhs == nil || rhs?.isEmpty == true

        if lhsEmpty && rhsEmpty {
            return true
        }

        return lhs == rhs
    }
}
