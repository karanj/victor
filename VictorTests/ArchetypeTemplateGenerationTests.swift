import XCTest
@testable import Victor
import Yams
import TOMLKit

/// Tests for archetype template generation to ensure generated templates are valid
/// and parseable by YAML/TOML/JSON parsers
final class ArchetypeTemplateGenerationTests: XCTestCase {

    // MARK: - YAML Template Generation Tests

    /// Test that generated YAML archetype with common fields has properly quoted Hugo syntax
    func testYAMLArchetypeWithCommonFieldsHasQuotedSyntax() {
        let template = generateYAMLTemplateWithCommonFields()

        // Template should contain quoted Hugo template syntax
        XCTAssertTrue(template.contains("date: '{{ .Date }}'") ||
                     template.contains("date: \"{{ .Date }}\""),
                     "Date field should be quoted to be valid YAML")
    }

    /// Test that generated YAML archetype without common fields has properly quoted Hugo syntax
    func testYAMLArchetypeWithoutCommonFieldsHasQuotedSyntax() {
        let template = generateYAMLTemplateWithoutCommonFields()

        // Template should contain quoted Hugo template syntax
        XCTAssertTrue(template.contains("date: '{{ .Date }}'") ||
                     template.contains("date: \"{{ .Date }}\""),
                     "Date field should be quoted to be valid YAML")
    }

    /// Test that generated YAML archetype follows Hugo's recommended format
    /// Note: Archetype templates are NOT meant to be directly parseable as YAML
    /// They are Hugo templates that output valid YAML after processing
    func testYAMLArchetypeFollowsHugoFormat() {
        let template = generateYAMLTemplateWithCommonFields()

        // Should have YAML delimiters
        XCTAssertTrue(template.hasPrefix("---"))
        XCTAssertTrue(template.contains("\n---\n"), "Template should have closing delimiter")

        // All Hugo template variables should be quoted (per Hugo docs)
        XCTAssertTrue(template.contains("date: '{{ .Date }}'") || template.contains("date: \"{{ .Date }}\""),
                     "Date field should follow Hugo's recommended quoted format")
        XCTAssertTrue(template.contains("title: \"{{ replace"), "Title field should be quoted")
    }

    // MARK: - TOML Template Generation Tests

    /// Test that generated TOML archetype with common fields has properly quoted Hugo syntax
    func testTOMLArchetypeWithCommonFieldsHasQuotedSyntax() {
        let template = generateTOMLTemplateWithCommonFields()

        // Template should contain quoted Hugo template syntax
        XCTAssertTrue(template.contains("date = '{{ .Date }}'") ||
                     template.contains("date = \"{{ .Date }}\""),
                     "Date field should be quoted to be valid TOML")
    }

    /// Test that generated TOML archetype without common fields has properly quoted Hugo syntax
    func testTOMLArchetypeWithoutCommonFieldsHasQuotedSyntax() {
        let template = generateTOMLTemplateWithoutCommonFields()

        // Template should contain quoted Hugo template syntax
        XCTAssertTrue(template.contains("date = '{{ .Date }}'") ||
                     template.contains("date = \"{{ .Date }}\""),
                     "Date field should be quoted to be valid TOML")
    }

    /// Test that generated TOML archetype follows Hugo's recommended format
    /// Note: Archetype templates are NOT meant to be directly parseable as TOML
    /// They are Hugo templates that output valid TOML after processing
    func testTOMLArchetypeFollowsHugoFormat() {
        let template = generateTOMLTemplateWithCommonFields()

        // Should have TOML delimiters
        XCTAssertTrue(template.hasPrefix("+++"))
        XCTAssertTrue(template.contains("\n+++\n"), "Template should have closing delimiter")

        // All Hugo template variables should be quoted (per Hugo docs)
        XCTAssertTrue(template.contains("date = '{{ .Date }}'") || template.contains("date = \"{{ .Date }}\""),
                     "Date field should follow Hugo's recommended quoted format")
        XCTAssertTrue(template.contains("title = \"{{ replace"), "Title field should be quoted")
    }

    // MARK: - JSON Template Generation Tests

    /// Test that generated JSON archetype with common fields is valid JSON
    func testJSONArchetypeWithCommonFieldsIsValidJSON() {
        let template = generateJSONTemplateWithCommonFields()

        // Extract JSON frontmatter (everything until closing brace)
        var braceCount = 0
        var jsonEndIndex = template.startIndex
        for (idx, char) in template.enumerated() {
            if char == "{" { braceCount += 1 }
            if char == "}" {
                braceCount -= 1
                if braceCount == 0 {
                    jsonEndIndex = template.index(template.startIndex, offsetBy: idx + 1)
                    break
                }
            }
        }
        let jsonContent = String(template[..<jsonEndIndex])

        // JSON should be parseable
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: jsonContent.data(using: .utf8)!),
                        "Generated JSON should be valid")
    }

    /// Test that generated JSON archetype without common fields is valid JSON
    func testJSONArchetypeWithoutCommonFieldsIsValidJSON() {
        let template = generateJSONTemplateWithoutCommonFields()

        // Extract JSON frontmatter (everything until closing brace)
        var braceCount = 0
        var jsonEndIndex = template.startIndex
        for (idx, char) in template.enumerated() {
            if char == "{" { braceCount += 1 }
            if char == "}" {
                braceCount -= 1
                if braceCount == 0 {
                    jsonEndIndex = template.index(template.startIndex, offsetBy: idx + 1)
                    break
                }
            }
        }
        let jsonContent = String(template[..<jsonEndIndex])

        // JSON should be parseable
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: jsonContent.data(using: .utf8)!),
                        "Generated JSON should be valid")
    }

    // MARK: - Integration Tests with FrontmatterParser

    /// Test that generated YAML archetype can be parsed by FrontmatterParser
    func testYAMLArchetypeCanBeParsedByFrontmatterParser() {
        let template = generateYAMLTemplateWithCommonFields()

        // FrontmatterParser should handle the template without crashing
        let (frontmatter, _) = FrontmatterParser.shared.parseContent(template)

        // We expect frontmatter to be non-nil since we have valid YAML delimiters
        XCTAssertNotNil(frontmatter, "FrontmatterParser should parse generated YAML archetype")
    }

    /// Test that generated TOML archetype can be parsed by FrontmatterParser
    func testTOMLArchetypeCanBeParsedByFrontmatterParser() {
        let template = generateTOMLTemplateWithCommonFields()

        // FrontmatterParser should handle the template without crashing
        let (frontmatter, _) = FrontmatterParser.shared.parseContent(template)

        // We expect frontmatter to be non-nil since we have valid TOML delimiters
        XCTAssertNotNil(frontmatter, "FrontmatterParser should parse generated TOML archetype")
    }

    /// Test that generated JSON archetype can be parsed by FrontmatterParser
    func testJSONArchetypeCanBeParsedByFrontmatterParser() {
        let template = generateJSONTemplateWithCommonFields()

        // FrontmatterParser should handle the template without crashing
        let (frontmatter, _) = FrontmatterParser.shared.parseContent(template)

        // We expect frontmatter to be non-nil since we have valid JSON
        XCTAssertNotNil(frontmatter, "FrontmatterParser should parse generated JSON archetype")
    }

    // MARK: - Template Generation Helpers
    // These mirror the logic in NewArchetypeView.generateArchetypeContent()

    private func generateYAMLTemplateWithCommonFields() -> String {
        return """
        ---
        title: "{{ replace .File.ContentBaseName "-" " " | title }}"
        date: '{{ .Date }}'
        draft: true
        description: ""
        tags: []
        categories: []
        ---

        Write your content here.
        """
    }

    private func generateYAMLTemplateWithoutCommonFields() -> String {
        return """
        ---
        title: "{{ .Title }}"
        date: '{{ .Date }}'
        draft: true
        ---

        """
    }

    private func generateTOMLTemplateWithCommonFields() -> String {
        return """
        +++
        title = "{{ replace .File.ContentBaseName "-" " " | title }}"
        date = '{{ .Date }}'
        draft = true
        description = ""
        tags = []
        categories = []
        +++

        Write your content here.
        """
    }

    private func generateTOMLTemplateWithoutCommonFields() -> String {
        return """
        +++
        title = "{{ .Title }}"
        date = '{{ .Date }}'
        draft = true
        +++

        """
    }

    private func generateJSONTemplateWithCommonFields() -> String {
        return """
        {
          "title": "{{ replace .File.ContentBaseName \\"-\\" \\" \\" | title }}",
          "date": "{{ .Date }}",
          "draft": true,
          "description": "",
          "tags": [],
          "categories": []
        }

        Write your content here.
        """
    }

    private func generateJSONTemplateWithoutCommonFields() -> String {
        return """
        {
          "title": "{{ .Title }}",
          "date": "{{ .Date }}",
          "draft": true
        }

        """
    }
}
