import Foundation

/// Manages loading and saving of specialized Hugo file types
///
/// Handles Hugo config, data files, templates, and archetypes.
/// Preserves unsaved edits when switching between files.
@MainActor
@Observable
final class SpecializedFileManager {

    // MARK: - Hugo Config

    /// Currently loaded Hugo configuration
    var hugoConfig: HugoConfig?

    /// Whether the Hugo config is currently loading
    var isLoadingConfig = false

    // MARK: - Data Files

    /// Per-file storage for data files - preserves unsaved edits when switching
    private var loadedDataFiles: [URL: DataFile] = [:]

    /// Whether a data file is currently loading
    var isLoadingDataFile = false

    /// Error from last data file load attempt
    var dataFileLoadError: String?

    /// URL of the last failed data file load
    var failedDataFileURL: URL?

    // MARK: - Templates

    /// Per-file storage for templates - preserves unsaved edits when switching
    private var loadedTemplates: [URL: Template] = [:]

    /// Whether a template is currently loading
    var isLoadingTemplate = false

    /// Error from last template load attempt
    var templateLoadError: String?

    /// URL of the last failed template load
    var failedTemplateURL: URL?

    // MARK: - Archetypes

    /// Per-file storage for archetypes - preserves unsaved edits when switching
    private var loadedArchetypes: [URL: Archetype] = [:]

    /// Whether an archetype is currently loading
    var isLoadingArchetype = false

    /// Error from last archetype load attempt
    var archetypeLoadError: String?

    /// URL of the last failed archetype load
    var failedArchetypeURL: URL?

    // MARK: - Initialization

    init() {}

    // MARK: - Hugo Config Methods

    /// Load Hugo configuration from a config file URL
    func loadHugoConfig(from url: URL) async throws {
        isLoadingConfig = true
        defer { isLoadingConfig = false }

        let config = try await HugoConfigParser.shared.parseConfig(at: url)
        hugoConfig = config
        Logger.shared.info("Loaded Hugo config: \(url.lastPathComponent)")
    }

    /// Save the current Hugo configuration (from form fields)
    func saveHugoConfig() async throws {
        guard let config = hugoConfig, let url = config.sourceURL else {
            throw SpecializedFileError.noFileToSave
        }

        let content = try HugoConfigParser.shared.serialize(config)
        try content.write(to: url, atomically: true, encoding: .utf8)
        config.rawContent = content
        config.markAsSaved()
        Logger.shared.info("Saved Hugo config: \(url.lastPathComponent)")
    }

    /// Save the current Hugo configuration directly from rawContent (for raw editor mode)
    func saveHugoConfigRaw() async throws {
        guard let config = hugoConfig, let url = config.sourceURL else {
            throw SpecializedFileError.noFileToSave
        }

        try config.rawContent.write(to: url, atomically: true, encoding: .utf8)
        config.markAsSaved()
        Logger.shared.info("Saved Hugo config (raw): \(url.lastPathComponent)")
    }

    // MARK: - Data File Methods

    /// Get a loaded data file by URL
    func getDataFile(for url: URL) -> DataFile? {
        return loadedDataFiles[url]
    }

    /// Set a data file for a URL
    func setDataFile(_ dataFile: DataFile?, for url: URL) {
        if let file = dataFile {
            loadedDataFiles[url] = file
        } else {
            loadedDataFiles.removeValue(forKey: url)
        }
    }

    /// Load a data file from URL (only loads from disk if not already in memory)
    func loadDataFile(from url: URL) async throws {
        // If already loaded, don't reload (preserves unsaved edits)
        if loadedDataFiles[url] != nil {
            isLoadingDataFile = false
            return
        }

        // Clear previous error state
        dataFileLoadError = nil
        failedDataFileURL = nil
        isLoadingDataFile = true
        defer { isLoadingDataFile = false }

        do {
            let dataFile = try await DataFileParser.shared.parseDataFile(at: url)
            loadedDataFiles[url] = dataFile
            Logger.shared.info("Loaded data file: \(url.lastPathComponent)")
        } catch {
            dataFileLoadError = error.localizedDescription
            failedDataFileURL = url
            throw error
        }
    }

    /// Save a data file
    func saveDataFile(_ dataFile: DataFile) async throws {
        try await DataFileParser.shared.save(dataFile)
        Logger.shared.info("Saved data file: \(dataFile.fileName)")
    }

    // MARK: - Template Methods

    /// Get a loaded template by URL
    func getTemplate(for url: URL) -> Template? {
        return loadedTemplates[url]
    }

    /// Set a template for a URL
    func setTemplate(_ template: Template?, for url: URL) {
        if let file = template {
            loadedTemplates[url] = file
        } else {
            loadedTemplates.removeValue(forKey: url)
        }
    }

    /// Load a template file from URL (only loads from disk if not already in memory)
    func loadTemplate(from url: URL) async throws {
        // If already loaded, don't reload (preserves unsaved edits)
        if loadedTemplates[url] != nil {
            isLoadingTemplate = false
            return
        }

        // Clear previous error state
        templateLoadError = nil
        failedTemplateURL = nil
        isLoadingTemplate = true
        defer { isLoadingTemplate = false }

        do {
            let template = try await TemplateParser.shared.parseTemplate(at: url)
            loadedTemplates[url] = template
            Logger.shared.info("Loaded template: \(url.lastPathComponent)")
        } catch {
            templateLoadError = error.localizedDescription
            failedTemplateURL = url
            throw error
        }
    }

    /// Save a template
    func saveTemplate(_ template: Template) async throws {
        try await TemplateParser.shared.save(template)
        Logger.shared.info("Saved template: \(template.fileName)")
    }

    // MARK: - Archetype Methods

    /// Get a loaded archetype by URL
    func getArchetype(for url: URL) -> Archetype? {
        return loadedArchetypes[url]
    }

    /// Set an archetype for a URL
    func setArchetype(_ archetype: Archetype?, for url: URL) {
        if let file = archetype {
            loadedArchetypes[url] = file
        } else {
            loadedArchetypes.removeValue(forKey: url)
        }
    }

    /// Load an archetype file from URL (only loads from disk if not already in memory)
    func loadArchetype(from url: URL) async throws {
        // If already loaded, don't reload (preserves unsaved edits)
        if loadedArchetypes[url] != nil {
            isLoadingArchetype = false
            return
        }

        // Clear previous error state
        archetypeLoadError = nil
        failedArchetypeURL = nil
        isLoadingArchetype = true
        defer { isLoadingArchetype = false }

        do {
            let archetype = try await parseArchetype(at: url)
            loadedArchetypes[url] = archetype
            Logger.shared.info("Loaded archetype: \(url.lastPathComponent)")
        } catch {
            archetypeLoadError = error.localizedDescription
            failedArchetypeURL = url
            throw error
        }
    }

    /// Save an archetype
    func saveArchetype(_ archetype: Archetype) async throws {
        try archetype.rawContent.write(to: archetype.url, atomically: true, encoding: .utf8)
        archetype.markAsSaved()
        Logger.shared.info("Saved archetype: \(archetype.fileName)")
    }

    /// Parse an archetype file from disk. `@MainActor`, so the blocking read goes through
    /// `readFileContentsOffActor` to genuinely leave the actor.
    private func parseArchetype(at url: URL) async throws -> Archetype {
        let content = try await readFileContentsOffActor(at: url)

        let lines = content.components(separatedBy: "\n")
        guard !lines.isEmpty else {
            return Archetype(url: url, frontmatterContent: "", bodyTemplate: content, frontmatterFormat: .yaml)
        }

        // Detect frontmatter format from first line
        let firstLine = lines[0].trimmingCharacters(in: .whitespaces)
        var format: FrontmatterFormat
        var delimiter: String

        if firstLine == "---" {
            format = .yaml
            delimiter = "---"
        } else if firstLine == "+++" {
            format = .toml
            delimiter = "+++"
        } else if firstLine.hasPrefix("{") {
            format = .json
            return try parseJSONArchetype(url: url, content: content, lines: lines)
        } else {
            // No frontmatter detected - treat entire file as body
            return Archetype(url: url, frontmatterContent: "", bodyTemplate: content, frontmatterFormat: .yaml)
        }

        // Find closing delimiter for YAML/TOML
        var frontmatterLines: [String] = []
        var bodyLines: [String] = []
        var foundClosing = false

        for (index, line) in lines.enumerated() {
            if index == 0 { continue } // Skip opening delimiter

            if line.trimmingCharacters(in: .whitespaces) == delimiter && !foundClosing {
                foundClosing = true
                continue
            }

            if foundClosing {
                bodyLines.append(line)
            } else {
                frontmatterLines.append(line)
            }
        }

        let frontmatter = frontmatterLines.joined(separator: "\n")
        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .newlines)

        return Archetype(url: url, frontmatterContent: frontmatter, bodyTemplate: body, frontmatterFormat: format)
    }

    /// Parse JSON frontmatter archetype
    private func parseJSONArchetype(url: URL, content: String, lines: [String]) throws -> Archetype {
        var braceCount = 0
        var endIndex = 0

        for (index, line) in lines.enumerated() {
            for char in line {
                if char == "{" { braceCount += 1 }
                if char == "}" { braceCount -= 1 }
            }
            if braceCount == 0 {
                endIndex = index
                break
            }
        }

        let frontmatter = lines[0...endIndex].joined(separator: "\n")
        let body = lines.dropFirst(endIndex + 1).joined(separator: "\n").trimmingCharacters(in: .newlines)

        return Archetype(url: url, frontmatterContent: frontmatter, bodyTemplate: body, frontmatterFormat: .json)
    }

    // MARK: - Unsaved Changes

    /// Check if any specialized files have unsaved changes
    var hasUnsavedChanges: Bool {
        if hugoConfig?.hasUnsavedChanges == true {
            return true
        }
        if loadedDataFiles.values.contains(where: { $0.hasUnsavedChanges }) {
            return true
        }
        if loadedTemplates.values.contains(where: { $0.hasUnsavedChanges }) {
            return true
        }
        if loadedArchetypes.values.contains(where: { $0.hasUnsavedChanges }) {
            return true
        }
        return false
    }

    /// Check if a specific file has unsaved changes
    func hasUnsavedChanges(for url: URL) -> Bool {
        if let config = hugoConfig, config.sourceURL == url, config.hasUnsavedChanges {
            return true
        }
        if let dataFile = loadedDataFiles[url], dataFile.hasUnsavedChanges {
            return true
        }
        if let template = loadedTemplates[url], template.hasUnsavedChanges {
            return true
        }
        if let archetype = loadedArchetypes[url], archetype.hasUnsavedChanges {
            return true
        }
        return false
    }

    /// Save all files with unsaved changes
    func saveAll() async {
        if hugoConfig?.hasUnsavedChanges == true {
            do {
                try await saveHugoConfig()
            } catch {
                Logger.shared.error("Failed to save Hugo config", error: error)
            }
        }

        for (_, dataFile) in loadedDataFiles where dataFile.hasUnsavedChanges {
            do {
                try await saveDataFile(dataFile)
            } catch {
                Logger.shared.error("Failed to save data file \(dataFile.fileName)", error: error)
            }
        }

        for (_, template) in loadedTemplates where template.hasUnsavedChanges {
            do {
                try await saveTemplate(template)
            } catch {
                Logger.shared.error("Failed to save template \(template.fileName)", error: error)
            }
        }

        for (_, archetype) in loadedArchetypes where archetype.hasUnsavedChanges {
            do {
                try await saveArchetype(archetype)
            } catch {
                Logger.shared.error("Failed to save archetype \(archetype.fileName)", error: error)
            }
        }
    }

    // MARK: - Clear

    /// Clear all loaded specialized files
    func clearAll() {
        hugoConfig = nil
        loadedDataFiles.removeAll()
        loadedTemplates.removeAll()
        loadedArchetypes.removeAll()
    }
}

// MARK: - Errors

enum SpecializedFileError: LocalizedError {
    case noFileToSave

    var errorDescription: String? {
        switch self {
        case .noFileToSave:
            return "No file to save"
        }
    }
}
