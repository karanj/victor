import Foundation

/// Represents the detected structure of a Hugo site
struct HugoSiteStructure {
    /// The root URL of the Hugo site
    let rootURL: URL

    /// Detected Hugo directories and whether they exist
    var detectedDirectories: [HugoRole: URL] = [:]

    /// The main config file URL (if found)
    var configFileURL: URL?

    /// The config file format (toml, yaml, or json)
    var configFormat: ConfigFormat?

    /// Whether this is a directory-based config (config/_default/)
    var hasDirectoryConfig: Bool = false

    /// Standard Hugo directories to scan
    static let standardDirectories: [String] = [
        "archetypes",
        "assets",
        "content",
        "data",
        "i18n",
        "layouts",
        "static",
        "themes",
        "config"
    ]

    /// Directories that should be excluded from scanning
    static let excludedDirectories: Set<String> = [
        "public",           // Build output
        "resources",        // Asset cache
        ".git",             // Git repository
        ".github",          // GitHub configuration
        "node_modules",     // Node dependencies
        ".hugo_build.lock", // Build lock
        "_vendor",          // Vendored modules
        ".DS_Store"         // macOS metadata
    ]

    /// Config file names to look for (in order of precedence)
    static let configFileNames: [String] = [
        "hugo.toml",
        "hugo.yaml",
        "hugo.json",
        "config.toml",
        "config.yaml",
        "config.json"
    ]

    // MARK: - Initialization

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    // MARK: - Detection

    /// Detect the Hugo site structure at the given URL
    static func detect(at url: URL) -> HugoSiteStructure {
        var structure = HugoSiteStructure(rootURL: url)
        let fileManager = FileManager.default

        // Detect standard Hugo directories
        for dirName in standardDirectories {
            let dirURL = url.appendingPathComponent(dirName)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue {
                if let role = HugoRole(directoryName: dirName) {
                    structure.detectedDirectories[role] = dirURL
                }
            }
        }

        // Detect config file
        for configName in configFileNames {
            let configURL = url.appendingPathComponent(configName)
            if fileManager.fileExists(atPath: configURL.path) {
                structure.configFileURL = configURL
                structure.configFormat = ConfigFormat(filename: configName)
                break
            }
        }

        // Check for directory-based config
        let configDirURL = url.appendingPathComponent("config")
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: configDirURL.path, isDirectory: &isDir), isDir.boolValue {
            let defaultConfigURL = configDirURL.appendingPathComponent("_default")
            if fileManager.fileExists(atPath: defaultConfigURL.path, isDirectory: &isDir), isDir.boolValue {
                structure.hasDirectoryConfig = true
            }
        }

        return structure
    }

    /// Check if a directory should be excluded from scanning
    static func shouldExclude(directoryName: String) -> Bool {
        excludedDirectories.contains(directoryName) ||
        directoryName.hasPrefix(".")
    }

    /// Check if a file is a Hugo config file
    static func isConfigFile(filename: String) -> Bool {
        configFileNames.contains(filename)
    }

    /// Check if this appears to be a valid Hugo site
    var isValidHugoSite: Bool {
        // A valid Hugo site has either a config file or a content directory
        configFileURL != nil || detectedDirectories[.content] != nil
    }

    /// Get all root-level items to display (directories + config files)
    func getRootItems() -> [RootItem] {
        var items: [RootItem] = []

        // Add detected directories in a consistent order
        let orderedRoles: [HugoRole] = [
            .archetypes, .assets, .content, .data, .i18n, .layouts, .staticFiles, .themes
        ]

        for role in orderedRoles {
            if let url = detectedDirectories[role] {
                items.append(RootItem(url: url, role: role, isConfigFile: false))
            }
        }

        // Add config file at the end
        if let configURL = configFileURL {
            items.append(RootItem(url: configURL, role: .config, isConfigFile: true))
        }

        return items
    }
}

// MARK: - Supporting Types

/// Represents a root-level item in the Hugo site
struct RootItem {
    let url: URL
    let role: HugoRole
    let isConfigFile: Bool

    var name: String {
        url.lastPathComponent
    }
}

/// Hugo configuration file format
enum ConfigFormat: String, Equatable {
    case toml
    case yaml
    case json

    init?(filename: String) {
        let lowercased = filename.lowercased()
        if lowercased.hasSuffix(".toml") {
            self = .toml
        } else if lowercased.hasSuffix(".yaml") || lowercased.hasSuffix(".yml") {
            self = .yaml
        } else if lowercased.hasSuffix(".json") {
            self = .json
        } else {
            return nil
        }
    }

    init?(extension ext: String) {
        switch ext.lowercased() {
        case "toml":
            self = .toml
        case "yaml", "yml":
            self = .yaml
        case "json":
            self = .json
        default:
            return nil
        }
    }

    var fileExtension: String {
        switch self {
        case .toml:
            return "toml"
        case .yaml:
            return "yaml"
        case .json:
            return "json"
        }
    }
}
