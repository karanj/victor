import XCTest
@testable import Victor

/// Tests for PermalinkResolver - converts content file paths to Hugo URLs
/// using the site's permalink configuration
final class PermalinkResolverTests: XCTestCase {

    // MARK: - No Permalink Config (default behavior)

    func testDefaultBehavior_simpleContentPath() {
        let resolver = PermalinkResolver(permalinks: [:])
        let result = resolver.resolveURL(
            filePath: "content/posts/my-post.md",
            date: nil,
            slug: nil
        )
        XCTAssertEqual(result, "/posts/my-post/")
    }

    func testDefaultBehavior_indexFile() {
        let resolver = PermalinkResolver(permalinks: [:])
        let result = resolver.resolveURL(
            filePath: "content/posts/_index.md",
            date: nil,
            slug: nil
        )
        XCTAssertEqual(result, "/posts/")
    }

    func testDefaultBehavior_rootIndex() {
        let resolver = PermalinkResolver(permalinks: [:])
        let result = resolver.resolveURL(
            filePath: "content/_index.md",
            date: nil,
            slug: nil
        )
        XCTAssertEqual(result, "/")
    }

    // MARK: - Permalink Pattern Expansion

    func testPermalink_yearMonthTitle() {
        let resolver = PermalinkResolver(permalinks: ["posts": "/:year/:month/:title/"])
        let date = makeDate(year: 2024, month: 3, day: 15)
        let result = resolver.resolveURL(
            filePath: "content/posts/my-post.md",
            date: date,
            slug: nil
        )
        XCTAssertEqual(result, "/2024/03/my-post/")
    }

    func testPermalink_yearMonthDayTitle() {
        let resolver = PermalinkResolver(permalinks: ["posts": "/:year/:month/:day/:title/"])
        let date = makeDate(year: 2025, month: 12, day: 5)
        let result = resolver.resolveURL(
            filePath: "content/posts/hello-world.md",
            date: date,
            slug: nil
        )
        XCTAssertEqual(result, "/2025/12/05/hello-world/")
    }

    func testPermalink_slugOverridesTitle() {
        let resolver = PermalinkResolver(permalinks: ["posts": "/:year/:month/:slug/"])
        let date = makeDate(year: 2024, month: 6, day: 1)
        let result = resolver.resolveURL(
            filePath: "content/posts/my-post.md",
            date: date,
            slug: "custom-slug"
        )
        XCTAssertEqual(result, "/2024/06/custom-slug/")
    }

    func testPermalink_titleTokenUsesSlugIfAvailable() {
        let resolver = PermalinkResolver(permalinks: ["posts": "/:year/:title/"])
        let date = makeDate(year: 2024, month: 1, day: 1)
        let result = resolver.resolveURL(
            filePath: "content/posts/original-name.md",
            date: date,
            slug: "overridden"
        )
        XCTAssertEqual(result, "/2024/overridden/")
    }

    func testPermalink_sectionToken() {
        let resolver = PermalinkResolver(permalinks: ["posts": "/:section/:year/:title/"])
        let date = makeDate(year: 2024, month: 1, day: 1)
        let result = resolver.resolveURL(
            filePath: "content/posts/my-post.md",
            date: date,
            slug: nil
        )
        XCTAssertEqual(result, "/posts/2024/my-post/")
    }

    func testPermalink_filenameToken() {
        let resolver = PermalinkResolver(permalinks: ["posts": "/:year/:filename/"])
        let date = makeDate(year: 2024, month: 1, day: 1)
        let result = resolver.resolveURL(
            filePath: "content/posts/my-post.md",
            date: date,
            slug: "custom-slug"
        )
        // :filename always uses the actual filename, not the slug
        XCTAssertEqual(result, "/2024/my-post/")
    }

    // MARK: - Section Matching

    func testPermalink_differentSections() {
        let resolver = PermalinkResolver(permalinks: [
            "posts": "/:year/:month/:title/",
            "articles": "/:year/:title/"
        ])
        let date = makeDate(year: 2024, month: 8, day: 20)

        let postsResult = resolver.resolveURL(
            filePath: "content/posts/my-post.md",
            date: date,
            slug: nil
        )
        XCTAssertEqual(postsResult, "/2024/08/my-post/")

        let articlesResult = resolver.resolveURL(
            filePath: "content/articles/my-article.md",
            date: date,
            slug: nil
        )
        XCTAssertEqual(articlesResult, "/2024/my-article/")
    }

    func testPermalink_sectionNotConfigured_fallsBackToDefault() {
        let resolver = PermalinkResolver(permalinks: ["posts": "/:year/:month/:title/"])
        let date = makeDate(year: 2024, month: 3, day: 15)
        let result = resolver.resolveURL(
            filePath: "content/pages/about.md",
            date: date,
            slug: nil
        )
        // No permalink pattern for "pages", falls back to default path
        XCTAssertEqual(result, "/pages/about/")
    }

    // MARK: - Index files should not use permalink patterns

    func testPermalink_indexFileIgnoresPattern() {
        let resolver = PermalinkResolver(permalinks: ["posts": "/:year/:month/:title/"])
        let result = resolver.resolveURL(
            filePath: "content/posts/_index.md",
            date: makeDate(year: 2024, month: 1, day: 1),
            slug: nil
        )
        // _index.md is a section page, permalink patterns don't apply
        XCTAssertEqual(result, "/posts/")
    }

    // MARK: - No date available

    func testPermalink_noDateFallsBackToDefault() {
        let resolver = PermalinkResolver(permalinks: ["posts": "/:year/:month/:title/"])
        let result = resolver.resolveURL(
            filePath: "content/posts/my-post.md",
            date: nil,
            slug: nil
        )
        // Can't expand date tokens without a date, fall back to default
        XCTAssertEqual(result, "/posts/my-post/")
    }

    // MARK: - Nested sections

    func testPermalink_nestedSection() {
        let resolver = PermalinkResolver(permalinks: ["blog": "/:year/:month/:title/"])
        let date = makeDate(year: 2024, month: 5, day: 10)
        let result = resolver.resolveURL(
            filePath: "content/blog/tech/my-post.md",
            date: date,
            slug: nil
        )
        // Top-level section is "blog", so the permalink pattern applies
        XCTAssertEqual(result, "/2024/05/my-post/")
    }

    // MARK: - Parsing from HugoConfig

    func testParsePermalinks_fromConfig() throws {
        let config = HugoConfig()
        config.permalinks = ["posts": "/:year/:month/:title/"]
        let permalinks = PermalinkResolver.parsePermalinks(from: config)
        XCTAssertEqual(permalinks, ["posts": "/:year/:month/:title/"])
    }

    func testParsePermalinks_emptyConfig() {
        let config = HugoConfig()
        let permalinks = PermalinkResolver.parsePermalinks(from: config)
        XCTAssertEqual(permalinks, [:])
    }

    // MARK: - HugoConfig dictionary init parsing

    func testHugoConfigParsesPermalinks_flatFormat() {
        let dict: [String: Any] = [
            "baseURL": "https://example.com/",
            "permalinks": ["posts": "/:year/:month/:title/"]
        ]
        let config = HugoConfig(from: dict, format: .toml, url: URL(fileURLWithPath: "/dev/null"))
        XCTAssertEqual(config.permalinks, ["posts": "/:year/:month/:title/"])
        // Should not appear in customFields
        XCTAssertNil(config.customFields["permalinks"])
    }

    func testHugoConfigParsesPermalinks_nestedPageFormat() {
        let dict: [String: Any] = [
            "baseURL": "https://example.com/",
            "permalinks": [
                "page": ["posts": "/:year/:month/:title/"],
                "section": ["posts": "/:year/"]
            ] as [String: Any]
        ]
        let config = HugoConfig(from: dict, format: .toml, url: URL(fileURLWithPath: "/dev/null"))
        XCTAssertEqual(config.permalinks, ["posts": "/:year/:month/:title/"])
    }

    // MARK: - Pattern Validation

    func testValidate_validPatterns() {
        let valid = [
            "/:year/:month/:title/",
            "/:year/:month/:day/:slug/",
            "/:section/:year/:title/",
            "/:year/:monthname/:filename/",
            "/:year/:weekdayname/:title/",
            "/:yearday/:title/",
            "/blog/:year/:month/:title/",
            "/:sections/:year/:title/",
            "/:weekday/:title/",
        ]
        for pattern in valid {
            let result = PermalinkResolver.validate(pattern: pattern)
            XCTAssertNil(result, "Expected valid but got error for: \(pattern) — \(result ?? "")")
        }
    }

    func testValidate_unknownToken() {
        let result = PermalinkResolver.validate(pattern: "/:year/:bogus/:title/")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("bogus"), "Error should mention the unknown token")
    }

    func testValidate_multipleUnknownTokens() {
        let result = PermalinkResolver.validate(pattern: "/:year/:foo/:bar/")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("foo"))
        XCTAssertTrue(result!.contains("bar"))
    }

    func testValidate_emptyPattern() {
        let result = PermalinkResolver.validate(pattern: "")
        XCTAssertNotNil(result, "Empty pattern should be invalid")
    }

    func testValidate_noLeadingSlash() {
        let result = PermalinkResolver.validate(pattern: ":year/:title/")
        XCTAssertNotNil(result, "Missing leading slash should be invalid")
    }

    func testValidate_noTokens() {
        let result = PermalinkResolver.validate(pattern: "/static-path/")
        // Valid — Hugo allows literal-only permalink patterns
        XCTAssertNil(result)
    }

    func testValidate_noTrailingSlash() {
        // Hugo requires trailing slash in permalinks
        let result = PermalinkResolver.validate(pattern: "/:year/:title")
        XCTAssertNotNil(result, "Missing trailing slash should be flagged")
    }

    func testValidate_sectionName_valid() {
        let valid = ["posts", "blog", "articles", "my-section", "docs"]
        for name in valid {
            let result = PermalinkResolver.validateSectionName(name)
            XCTAssertNil(result, "Expected valid section name: \(name) — \(result ?? "")")
        }
    }

    func testValidate_sectionName_empty() {
        let result = PermalinkResolver.validateSectionName("")
        XCTAssertNotNil(result)
    }

    func testValidate_sectionName_withSlashes() {
        let result = PermalinkResolver.validateSectionName("posts/sub")
        XCTAssertNotNil(result, "Section names should not contain slashes")
    }

    func testValidate_sectionName_withSpaces() {
        let result = PermalinkResolver.validateSectionName("my posts")
        XCTAssertNotNil(result, "Section names should not contain spaces")
    }

    // MARK: - Token List

    func testValidTokens_containsExpectedTokens() {
        let tokens = PermalinkResolver.validTokens
        XCTAssertTrue(tokens.contains { $0.token == ":year" })
        XCTAssertTrue(tokens.contains { $0.token == ":month" })
        XCTAssertTrue(tokens.contains { $0.token == ":day" })
        XCTAssertTrue(tokens.contains { $0.token == ":title" })
        XCTAssertTrue(tokens.contains { $0.token == ":slug" })
        XCTAssertTrue(tokens.contains { $0.token == ":section" })
        XCTAssertTrue(tokens.contains { $0.token == ":filename" })
    }

    func testValidTokens_haveDescriptions() {
        for tokenInfo in PermalinkResolver.validTokens {
            XCTAssertFalse(tokenInfo.description.isEmpty, "Token \(tokenInfo.token) missing description")
            XCTAssertFalse(tokenInfo.example.isEmpty, "Token \(tokenInfo.token) missing example")
        }
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}
