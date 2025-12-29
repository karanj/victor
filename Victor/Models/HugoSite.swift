import Foundation

/// Represents a Hugo static site
@Observable
class HugoSite: Identifiable {
    let id: UUID
    let rootURL: URL
    var contentDirectory: URL
    var configFile: URL?
    var theme: String?

    /// Display name derived from the folder name
    var displayName: String {
        rootURL.lastPathComponent
    }

    /// Security-scoped bookmark data for persistent access
    var bookmarkData: Data?

    /// Private initializer - use `create(rootURL:)` for async creation
    private init(rootURL: URL, configFile: URL?) {
        self.id = UUID()
        self.rootURL = rootURL
        self.contentDirectory = rootURL.appendingPathComponent("content")
        self.configFile = configFile
    }

    /// Create a HugoSite asynchronously, performing file I/O on a background thread
    static func create(rootURL: URL) async -> HugoSite {
        await Task.detached {
            // Try to find Hugo config file
            let possibleConfigs = [
                "hugo.toml", "hugo.yaml", "hugo.yml", "hugo.json",
                "config.toml", "config.yaml", "config.yml", "config.json"
            ]

            var foundConfig: URL?
            for configName in possibleConfigs {
                let configURL = rootURL.appendingPathComponent(configName)
                if FileManager.default.fileExists(atPath: configURL.path) {
                    foundConfig = configURL
                    break
                }
            }

            return HugoSite(rootURL: rootURL, configFile: foundConfig)
        }.value
    }

    /// Check if this appears to be a valid Hugo site (async version)
    /// Performs file existence check on a background thread
    func validateAsync() async -> Bool {
        await Task.detached {
            // A valid Hugo site should have a content directory or a config file
            FileManager.default.fileExists(atPath: self.contentDirectory.path) || self.configFile != nil
        }.value
    }

    /// Check if this appears to be a valid Hugo site (sync version)
    /// Note: Prefer validateAsync() in async contexts to avoid blocking
    var isValid: Bool {
        // A valid Hugo site should have a content directory or a config file
        FileManager.default.fileExists(atPath: contentDirectory.path) || configFile != nil
    }
}
