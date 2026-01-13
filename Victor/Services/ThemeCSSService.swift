import Foundation

/// Service for loading and caching CSS from Hugo themes
/// Uses actor isolation for thread-safe cache access
actor ThemeCSSService {
    static let shared = ThemeCSSService()

    /// Cache of loaded theme CSS, keyed by "{siteRootPath}:{themeName}"
    private var cache: [String: String] = [:]

    private init() {}

    // MARK: - Public API

    /// Load CSS from a Hugo theme's static/css directory
    /// - Parameters:
    ///   - themeName: Theme name from Hugo config (may be comma-separated for composition)
    ///   - siteRootURL: Root URL of the Hugo site
    /// - Returns: Combined CSS from theme(s), or nil if no CSS found
    func loadThemeCSS(themeName: String?, siteRootURL: URL?) async -> String? {
        guard let themeName = themeName, !themeName.isEmpty,
              let siteRoot = siteRootURL else {
            return nil
        }

        let cacheKey = "\(siteRoot.path):\(themeName)"

        // Return cached CSS if available
        if let cached = cache[cacheKey] {
            Logger.shared.debug("ThemeCSSService: Using cached CSS for \(themeName)")
            return cached
        }

        // Handle theme composition (comma-separated themes)
        // Format: "child-theme, parent-theme" - child overrides parent
        let themes = themeName.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        var combinedCSS = ""

        // Load in reverse order (parent first, child last) for correct CSS cascade
        for theme in themes.reversed() {
            if let css = loadCSSFromTheme(theme, siteRoot: siteRoot) {
                combinedCSS += "\n/* === Theme: \(theme) === */\n" + css
                Logger.shared.info("ThemeCSSService: Loaded CSS from theme '\(theme)'")
            } else {
                Logger.shared.warning("ThemeCSSService: No CSS found for theme '\(theme)'")
            }
        }

        // Cache the result (even if empty, to avoid repeated lookups)
        let result = combinedCSS.isEmpty ? nil : combinedCSS
        if let css = result {
            cache[cacheKey] = css
        }

        return result
    }

    /// Clear entire cache (call when app resets)
    func clearCache() {
        cache.removeAll()
        Logger.shared.debug("ThemeCSSService: Cleared all cache")
    }

    /// Clear cache for a specific site (call when site is closed)
    /// - Parameter siteRootURL: Root URL of the site to clear
    func clearCache(for siteRootURL: URL) {
        let prefix = siteRootURL.path + ":"
        let keysToRemove = cache.keys.filter { $0.hasPrefix(prefix) }
        for key in keysToRemove {
            cache.removeValue(forKey: key)
        }
        if !keysToRemove.isEmpty {
            Logger.shared.debug("ThemeCSSService: Cleared cache for \(siteRootURL.lastPathComponent)")
        }
    }

    // MARK: - Private Helpers

    /// Load all CSS files from a single theme's static/css directory
    /// - Parameters:
    ///   - themeName: Name of the theme directory
    ///   - siteRoot: Root URL of the Hugo site
    /// - Returns: Combined CSS content, or nil if no CSS files found
    private func loadCSSFromTheme(_ themeName: String, siteRoot: URL) -> String? {
        let themeCSSDir = siteRoot
            .appendingPathComponent("themes")
            .appendingPathComponent(themeName)
            .appendingPathComponent("static")
            .appendingPathComponent("css")

        guard FileManager.default.fileExists(atPath: themeCSSDir.path) else {
            // Also try without /css subdirectory (some themes put CSS directly in static/)
            let alternateDir = siteRoot
                .appendingPathComponent("themes")
                .appendingPathComponent(themeName)
                .appendingPathComponent("static")

            return loadCSSFilesFromDirectory(alternateDir)
        }

        return loadCSSFilesFromDirectory(themeCSSDir)
    }

    /// Load and combine all .css files from a directory
    /// - Parameter directory: Directory URL to scan
    /// - Returns: Combined CSS content, or nil if no CSS files found
    private func loadCSSFilesFromDirectory(_ directory: URL) -> String? {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return nil
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            // Filter to only .css files and sort alphabetically for consistent ordering
            let cssFiles = contents
                .filter { $0.pathExtension.lowercased() == "css" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            guard !cssFiles.isEmpty else {
                return nil
            }

            var combinedCSS = ""
            for cssFile in cssFiles {
                if let content = try? String(contentsOf: cssFile, encoding: .utf8) {
                    combinedCSS += "\n/* File: \(cssFile.lastPathComponent) */\n" + content
                } else {
                    Logger.shared.warning("ThemeCSSService: Failed to read \(cssFile.lastPathComponent)")
                }
            }

            return combinedCSS.isEmpty ? nil : combinedCSS
        } catch {
            Logger.shared.warning("ThemeCSSService: Error scanning \(directory.path): \(error.localizedDescription)")
            return nil
        }
    }
}
