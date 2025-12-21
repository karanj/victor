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

    init(rootURL: URL) {
        self.id = UUID()
        self.rootURL = rootURL
        // Hugo's default content directory
        self.contentDirectory = rootURL.appendingPathComponent("content")

        // Try to find Hugo config file
        let possibleConfigs = [
            "hugo.toml", "hugo.yaml", "hugo.yml", "hugo.json",
            "config.toml", "config.yaml", "config.yml", "config.json"
        ]

        for configName in possibleConfigs {
            let configURL = rootURL.appendingPathComponent(configName)
            if FileManager.default.fileExists(atPath: configURL.path) {
                self.configFile = configURL
                break
            }
        }
    }

    /// Check if this appears to be a valid Hugo site
    var isValid: Bool {
        // A valid Hugo site should have a content directory or a config file
        FileManager.default.fileExists(atPath: contentDirectory.path) || configFile != nil
    }
}
