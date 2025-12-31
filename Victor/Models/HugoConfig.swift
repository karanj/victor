import Foundation
import SwiftUI

/// Represents a Hugo site configuration
@Observable
class HugoConfig {
    // MARK: - Required Fields

    /// The base URL of the site (e.g., "https://example.com/")
    var baseURL: String = ""

    /// The site title
    var title: String = ""

    /// Language code (e.g., "en-us")
    var languageCode: String = "en-us"

    // MARK: - Common Fields

    /// Theme name or array of themes (comma-separated if multiple)
    var theme: String?

    /// Whether the theme was originally specified as an array (even if single item)
    var themeIsArray: Bool = false

    /// Copyright notice
    var copyright: String?

    /// Whether to include draft content in builds
    var buildDrafts: Bool = false

    /// Whether to include future-dated content
    var buildFuture: Bool = false

    /// Whether to include expired content
    var buildExpired: Bool = false

    /// Whether to generate robots.txt
    var enableRobotsTXT: Bool = false

    /// Summary length for auto-generated summaries
    var summaryLength: Int = 70

    /// Default content language
    var defaultContentLanguage: String = "en"

    /// Time zone for dates
    var timeZone: String?

    // MARK: - Taxonomies

    /// Custom taxonomies (singular: plural)
    var taxonomies: [String: String] = [
        "category": "categories",
        "tag": "tags"
    ]

    // MARK: - Menus

    /// Menu definitions
    var menus: [String: [HugoMenuItem]] = [:]

    // MARK: - Custom Parameters

    /// Site-specific custom parameters (params section)
    var params: [String: Any] = [:]

    // MARK: - Unknown Fields

    /// Fields not recognized by Victor (preserved for round-trip)
    var customFields: [String: Any] = [:]

    // MARK: - Metadata

    /// The source file URL
    var sourceURL: URL?

    /// The original format of the config file
    var sourceFormat: ConfigFormat = .toml

    /// The raw file content from disk (for raw view)
    var rawContent: String = ""

    /// Whether there are unsaved changes
    var hasUnsavedChanges: Bool = false

    // MARK: - Initialization

    init() {}

    init(from dictionary: [String: Any], format: ConfigFormat, url: URL, rawContent: String = "") {
        self.sourceURL = url
        self.sourceFormat = format
        self.rawContent = rawContent

        // Parse known fields
        if let baseURL = dictionary["baseURL"] as? String {
            self.baseURL = baseURL
        }
        if let title = dictionary["title"] as? String {
            self.title = title
        }
        if let languageCode = dictionary["languageCode"] as? String {
            self.languageCode = languageCode
        }
        // Theme can be a string or array of strings (for theme composition)
        if let theme = dictionary["theme"] as? String {
            self.theme = theme
            self.themeIsArray = false
        } else if let themes = dictionary["theme"] as? [String] {
            // Store as comma-separated for array format
            self.theme = themes.joined(separator: ", ")
            self.themeIsArray = true
        } else if let themes = dictionary["theme"] as? [Any] {
            // Handle mixed array types
            let themeStrings = themes.compactMap { $0 as? String }
            if !themeStrings.isEmpty {
                self.theme = themeStrings.joined(separator: ", ")
                self.themeIsArray = true
            }
        }
        if let copyright = dictionary["copyright"] as? String {
            self.copyright = copyright
        }
        if let buildDrafts = dictionary["buildDrafts"] as? Bool {
            self.buildDrafts = buildDrafts
        }
        if let buildFuture = dictionary["buildFuture"] as? Bool {
            self.buildFuture = buildFuture
        }
        if let buildExpired = dictionary["buildExpired"] as? Bool {
            self.buildExpired = buildExpired
        }
        if let enableRobotsTXT = dictionary["enableRobotsTXT"] as? Bool {
            self.enableRobotsTXT = enableRobotsTXT
        }
        if let summaryLength = dictionary["summaryLength"] as? Int {
            self.summaryLength = summaryLength
        }
        if let defaultContentLanguage = dictionary["defaultContentLanguage"] as? String {
            self.defaultContentLanguage = defaultContentLanguage
        }
        if let timeZone = dictionary["timeZone"] as? String {
            self.timeZone = timeZone
        }
        if let taxonomies = dictionary["taxonomies"] as? [String: String] {
            self.taxonomies = taxonomies
        }
        if let params = dictionary["params"] as? [String: Any] {
            self.params = params
        }

        // Parse menus
        if let menusDict = dictionary["menus"] as? [String: [[String: Any]]] {
            for (menuName, items) in menusDict {
                menus[menuName] = items.compactMap { HugoMenuItem(from: $0) }
            }
        } else if let menuDict = dictionary["menu"] as? [String: [[String: Any]]] {
            // Also check for "menu" (singular) which some configs use
            for (menuName, items) in menuDict {
                menus[menuName] = items.compactMap { HugoMenuItem(from: $0) }
            }
        }

        // Store all other fields as custom
        let knownFields: Set<String> = [
            "baseURL", "title", "languageCode", "theme", "copyright",
            "buildDrafts", "buildFuture", "buildExpired", "enableRobotsTXT",
            "summaryLength", "defaultContentLanguage", "timeZone",
            "taxonomies", "params", "menus", "menu"
        ]

        for (key, value) in dictionary where !knownFields.contains(key) {
            customFields[key] = value
        }
    }
}

/// Represents a menu item in Hugo config
struct HugoMenuItem: Identifiable {
    let id: UUID
    var name: String
    var url: String?
    var pageRef: String?
    var weight: Int
    var identifier: String?
    var parent: String?

    init(name: String, url: String? = nil, pageRef: String? = nil, weight: Int = 0, identifier: String? = nil, parent: String? = nil) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.pageRef = pageRef
        self.weight = weight
        self.identifier = identifier
        self.parent = parent
    }

    init?(from dictionary: [String: Any]) {
        guard let name = dictionary["name"] as? String else {
            return nil
        }
        self.id = UUID()
        self.name = name
        self.url = dictionary["url"] as? String
        self.pageRef = dictionary["pageRef"] as? String
        self.weight = dictionary["weight"] as? Int ?? 0
        self.identifier = dictionary["identifier"] as? String
        self.parent = dictionary["parent"] as? String
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = ["name": name]
        if let url = url { dict["url"] = url }
        if let pageRef = pageRef { dict["pageRef"] = pageRef }
        if weight != 0 { dict["weight"] = weight }
        if let identifier = identifier { dict["identifier"] = identifier }
        if let parent = parent { dict["parent"] = parent }
        return dict
    }
}
