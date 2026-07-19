import Foundation
import SwiftUI

/// Represents a Hugo site configuration.
///
/// Phase 1c (CONFIG-SCHEMA-SPEC §2.9): backed by `ConfigValueStore`. The 13
/// legacy typed fields below are computed accessors over the store — getters
/// fall back to Hugo's default when the key is absent, setters write through
/// `store.set`/`store.remove`, which is what marks a key present or absent.
/// Presence is now purely structural ("is this key in the store"), replacing
/// the Phase 0 `presentRootKeys`/`loadedTypedValues` bridge.
@Observable
class HugoConfig: EditableFile {
    // MARK: - Identification

    /// Unique identifier for this config
    let id: UUID = UUID()

    // MARK: - Backing Store

    /// Sparse key-path store. NOT observable itself (`@ObservationIgnored`
    /// internally) — every computed accessor below reads `store.version`
    /// first so SwiftUI still invalidates on mutation (CLAUDE.md's
    /// Per-Keystroke Invalidation Contract / CONFIG-SCHEMA-SPEC §2.8).
    let store: ConfigValueStore

    // MARK: - Required Fields

    /// The base URL of the site (e.g., "https://example.com/")
    var baseURL: String {
        get { tracked { store.stringValue("baseURL") ?? "" } }
        set { store.set(newValue, at: "baseURL") }
    }

    /// The site title
    var title: String {
        get { tracked { store.stringValue("title") ?? "" } }
        set { store.set(newValue, at: "title") }
    }

    /// Language code (e.g., "en-us"). Hugo-accurate default is "" (empty) —
    /// Hugo itself has no default for this deprecated key. No existing test
    /// depends on the historical Victor default of "en-us" when absent, so
    /// this getter's fallback flips to match Hugo (CONFIG-SCHEMA-SPEC §2.9).
    var languageCode: String {
        get { tracked { store.stringValue("languageCode") ?? "" } }
        set { store.set(newValue, at: "languageCode") }
    }

    // MARK: - Common Fields

    /// Theme name or array of themes (comma-separated if multiple). Stored in
    /// the underlying config in whatever shape (string or array) the source
    /// file used — shape preservation is structural, not flag-based.
    var theme: String? {
        get {
            tracked {
                guard let raw = store.value(at: "theme") else { return nil }
                if let string = raw as? String { return string.isEmpty ? nil : string }
                if let array = store.stringArrayValue("theme"), !array.isEmpty {
                    return array.joined(separator: ", ")
                }
                return nil
            }
        }
        set {
            guard let newValue, !newValue.isEmpty else {
                store.remove(at: "theme")
                return
            }
            if newValue.contains(", ") {
                let parts = newValue.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }
                store.set(parts, at: "theme")
            } else {
                store.set(newValue, at: "theme")
            }
        }
    }

    /// Whether the theme is currently stored as an array (even if single item).
    /// Derived from the stored shape; kept for source compatibility with call
    /// sites written against the old flag-based field.
    var themeIsArray: Bool {
        get {
            tracked {
                let raw = store.value(at: "theme")
                return raw is [Any] || raw is [String]
            }
        }
        set {
            guard let current = theme else { return }
            if newValue {
                let parts = current.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }
                store.set(parts, at: "theme")
            } else {
                store.set(current, at: "theme")
            }
        }
    }

    /// Copyright notice
    var copyright: String? {
        get {
            tracked {
                let string = store.stringValue("copyright")
                return (string?.isEmpty ?? true) ? nil : string
            }
        }
        set {
            if let newValue, !newValue.isEmpty {
                store.set(newValue, at: "copyright")
            } else {
                store.remove(at: "copyright")
            }
        }
    }

    /// Whether to include draft content in builds
    var buildDrafts: Bool {
        get { tracked { store.boolValue("buildDrafts") ?? false } }
        set { store.set(newValue, at: "buildDrafts") }
    }

    /// Whether to include future-dated content
    var buildFuture: Bool {
        get { tracked { store.boolValue("buildFuture") ?? false } }
        set { store.set(newValue, at: "buildFuture") }
    }

    /// Whether to include expired content
    var buildExpired: Bool {
        get { tracked { store.boolValue("buildExpired") ?? false } }
        set { store.set(newValue, at: "buildExpired") }
    }

    /// Whether to generate robots.txt
    var enableRobotsTXT: Bool {
        get { tracked { store.boolValue("enableRobotsTXT") ?? false } }
        set { store.set(newValue, at: "enableRobotsTXT") }
    }

    /// Summary length for auto-generated summaries (Hugo default: 70)
    var summaryLength: Int {
        get { tracked { store.intValue("summaryLength") ?? 70 } }
        set { store.set(newValue, at: "summaryLength") }
    }

    /// Default content language (Hugo default: "en")
    var defaultContentLanguage: String {
        get { tracked { store.stringValue("defaultContentLanguage") ?? "en" } }
        set { store.set(newValue, at: "defaultContentLanguage") }
    }

    /// Time zone for dates
    var timeZone: String? {
        get {
            tracked {
                let string = store.stringValue("timeZone")
                return (string?.isEmpty ?? true) ? nil : string
            }
        }
        set {
            if let newValue, !newValue.isEmpty {
                store.set(newValue, at: "timeZone")
            } else {
                store.remove(at: "timeZone")
            }
        }
    }

    // MARK: - Taxonomies

    /// Custom taxonomies (singular: plural). Falls back to Hugo's default
    /// pair when absent; the fallback is never written until the store is
    /// actually touched (design-doc issue #2: explicit declarations of the
    /// default still round-trip, because presence is structural).
    var taxonomies: [String: String] {
        get {
            tracked {
                (store.value(at: "taxonomies") as? [String: String]) ?? ["category": "categories", "tag": "tags"]
            }
        }
        set {
            if newValue.isEmpty {
                store.remove(at: "taxonomies")
            } else {
                store.set(newValue, at: "taxonomies")
            }
        }
    }

    // MARK: - Permalinks

    /// Permalink patterns keyed by section name (e.g. ["posts": "/:year/:month/:title/"]).
    /// Reads either the flat `[permalinks]` shape or the nested `[permalinks.page]`
    /// shape Hugo also accepts; always writes the flat shape.
    var permalinks: [String: String] {
        get {
            tracked {
                guard let raw = store.value(at: "permalinks") else { return [:] }
                if let flat = raw as? [String: String] { return flat }
                if let nested = raw as? [String: Any], let page = nested["page"] as? [String: String] {
                    return page
                }
                return [:]
            }
        }
        set {
            if newValue.isEmpty {
                store.remove(at: "permalinks")
            } else {
                store.set(newValue, at: "permalinks")
            }
        }
    }

    // MARK: - Menus

    /// Menu definitions. The one documented exception to the store-computed
    /// pattern: menus stay a typed materialization (CONFIG-SCHEMA-SPEC §2.9,
    /// §3.4) — parsed from the store on load/`updateFromRawContent`, written
    /// back through `commitMenus()`, the single write path.
    var menus: [String: [HugoMenuItem]] = [:]

    /// Spelling of the menu root key in the source file ("menu" or "menus").
    /// Hugo accepts both; we must not silently rename the user's key.
    /// New configs use "menus" (Hugo's documented name).
    @ObservationIgnored var menuKeySpelling: String = "menus"

    /// Rebuilds `menus` from whatever's currently under `menuKeySpelling` in
    /// the store. Called at init and after a full store replacement
    /// (Raw→Form re-parse).
    private func materializeMenus() {
        guard let menuDict = store.subtree(menuKeySpelling) else {
            menus = [:]
            return
        }
        var result: [String: [HugoMenuItem]] = [:]
        for (menuName, itemsAny) in menuDict {
            guard let items = itemsAny as? [[String: Any]] else { continue }
            result[menuName] = items.compactMap { HugoMenuItem(from: $0) }
        }
        menus = result
    }

    /// Writes `menus` back into the store under `menuKeySpelling`. Empty
    /// menus prune the key entirely, matching every other dict-valued field's
    /// presence policy. Called by `HugoConfigParser.serialize` before it
    /// snapshots the store, so menus are never stale at save time.
    func commitMenus() {
        guard !menus.isEmpty else {
            store.remove(at: menuKeySpelling)
            return
        }
        let menuDict: [String: [[String: Any]]] = menus.mapValues { items in items.map { $0.toDictionary() } }
        store.replaceSubtree(menuKeySpelling, with: menuDict.mapValues { $0 as Any })
    }

    // MARK: - Custom Parameters

    /// Site-specific custom parameters (params section)
    var params: [String: Any] {
        get { tracked { store.subtree("params") ?? [:] } }
        set {
            if newValue.isEmpty {
                store.remove(at: "params")
            } else {
                store.replaceSubtree("params", with: newValue)
            }
        }
    }

    // MARK: - Unknown Fields

    /// Root keys with no dedicated HugoConfig field — everything the schema
    /// doesn't materialize. Read-only: unknown keys live directly in the
    /// store and round-trip through it; this is just a view for display
    /// (Advanced tab's "Other Fields (Preserved)" section).
    private static let knownRootKeys: Set<String> = [
        "baseURL", "title", "languageCode", "theme", "copyright",
        "buildDrafts", "buildFuture", "buildExpired", "enableRobotsTXT",
        "summaryLength", "defaultContentLanguage", "timeZone",
        "taxonomies", "permalinks", "params", "menus", "menu"
    ]

    var customFields: [String: Any] {
        tracked {
            var result: [String: Any] = [:]
            for (key, value) in store.snapshotRoot() where !Self.knownRootKeys.contains(key) {
                result[key] = value
            }
            return result
        }
    }

    // MARK: - Metadata

    /// The source file URL
    var sourceURL: URL?

    /// The original format of the config file
    var sourceFormat: ConfigFormat = .toml

    /// Root keys present in the source file (or since set by the user). This
    /// is now purely structural — "is this key in the store" — replacing the
    /// Phase 0 presence bridge (CONFIG-SCHEMA-SPEC §2.9 item 6).
    var presentRootKeys: Set<String> {
        tracked { Set(store.snapshotRoot().keys) }
    }

    // MARK: - Raw Content

    /// The raw file content from disk (for raw view)
    var rawContent: String = ""

    /// The original content at the time of last save/load (for change detection)
    @ObservationIgnored private var originalContent: String = ""

    /// Whether there are unsaved changes (computed property comparing rawContent to originalContent)
    var hasUnsavedChanges: Bool {
        rawContent != originalContent
    }

    // MARK: - EditableFile Protocol

    /// File URL (required by EditableFile protocol)
    var url: URL {
        sourceURL ?? URL(fileURLWithPath: "/tmp/hugo.toml")
    }

    /// Mark the current state as saved (reset change tracking)
    func markAsSaved() {
        originalContent = rawContent
    }

    /// Update rawContent from current structured properties
    /// Call this when editing in form mode to trigger change detection
    func syncRawContentFromStructuredData() {
        do {
            rawContent = try HugoConfigParser.shared.serialize(self)
        } catch {
            print("[HugoConfig] Failed to sync rawContent: \(error)")
        }
    }

    // MARK: - Initialization

    /// - Parameter store: seeded store backing this config. Defaults to an
    ///   empty store for a brand-new (unsaved) config.
    init(store: ConfigValueStore = ConfigValueStore(root: [:])) {
        self.store = store
        // Favor "menus" per Hugo's documented spelling; only detect "menu"
        // when the file used the singular form exclusively.
        if store.isPresent("menu") && !store.isPresent("menus") {
            menuKeySpelling = "menu"
        }
        materializeMenus()
        // When creating a new config, mark it as saved (empty is considered saved).
        markAsSaved()
    }

    /// Update structured properties from rawContent
    /// Call this when switching from Raw to Form view
    func updateFromRawContent() throws {
        guard !rawContent.isEmpty else { return }

        // Debug: log what we're trying to parse
        let preview = String(rawContent.prefix(100)).replacingOccurrences(of: "\n", with: "\\n")
        print("[HugoConfig] Parsing \(sourceFormat.rawValue.uppercased()) content (\(rawContent.count) chars): \(preview)...")

        do {
            let parsed = try HugoConfigParser.shared.parseConfig(content: rawContent, format: sourceFormat)

            // Rebuild the store wholesale from the re-parse, then
            // re-materialize the menus/spelling that live outside it.
            store.replaceRoot(with: parsed.store.snapshotRoot(), orderedRootKeys: parsed.store.orderedRootKeys)
            menuKeySpelling = parsed.menuKeySpelling
            materializeMenus()

            print("[HugoConfig] Parse successful")
        } catch {
            print("[HugoConfig] Parse failed: \(error)")
            // Re-throw with more context about what we were trying to parse
            throw ConfigParseError.failedToParse(
                format: sourceFormat,
                contentPreview: preview,
                underlyingError: error
            )
        }
    }
}

/// Error type for config parsing with context
enum ConfigParseError: LocalizedError {
    case failedToParse(format: ConfigFormat, contentPreview: String, underlyingError: Error)

    var errorDescription: String? {
        switch self {
        case .failedToParse(let format, let contentPreview, let underlyingError):
            return "Failed to parse \(format.rawValue.uppercased()). Content starts with: \(contentPreview)\n\nError: \(underlyingError.localizedDescription)"
        }
    }
}

// MARK: - HugoConfig Dictionary Initializer

extension HugoConfig {
    /// - Parameter dictionary: the parsed config, seeded directly into a
    ///   fresh `ConfigValueStore` — normalization already happened once in
    ///   `HugoConfigParser.parse`, and the store re-normalizes defensively
    ///   at construction (harmless double-normalize, CONFIG-SCHEMA-SPEC §2.9
    ///   item 1). All shape preservation (theme string-vs-array, permalinks
    ///   flat-vs-nested, menu/menus spelling) now falls out of the store
    ///   holding the raw dictionary verbatim, rather than bespoke per-field
    ///   parsing.
    convenience init(from dictionary: [String: Any], format: ConfigFormat, url: URL, rawContent: String = "", orderedRootKeys: [String]? = nil) {
        self.init(store: ConfigValueStore(root: dictionary, orderedRootKeys: orderedRootKeys))
        self.sourceURL = url
        self.sourceFormat = format
        self.rawContent = rawContent

        // Mark as saved since we just loaded from disk
        markAsSaved()
    }
}

/// Represents a menu item in Hugo config
struct HugoMenuItem: Identifiable {
    /// Keys with dedicated properties; everything else round-trips via `extra`.
    private static let knownKeys: Set<String> = [
        "name", "url", "pageRef", "weight", "identifier", "parent", "title"
    ]

    let id: UUID
    var name: String
    var url: String?
    var pageRef: String?
    var weight: Int
    var identifier: String?
    var parent: String?
    /// Tooltip text (Hugo `title`)
    var title: String?
    /// Fields Victor doesn't edit (pre, post, params, …) — preserved so a
    /// form-mode save never drops them (CONFIG-SCHEMA-SPEC finding #8)
    var extra: [String: Any]

    init(name: String, url: String? = nil, pageRef: String? = nil, weight: Int = 0, identifier: String? = nil, parent: String? = nil, title: String? = nil, extra: [String: Any] = [:]) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.pageRef = pageRef
        self.weight = weight
        self.identifier = identifier
        self.parent = parent
        self.title = title
        self.extra = extra
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
        self.title = dictionary["title"] as? String
        self.extra = dictionary.filter { !Self.knownKeys.contains($0.key) }
    }

    func toDictionary() -> [String: Any] {
        var dict = extra
        dict["name"] = name
        if let url = url { dict["url"] = url }
        if let pageRef = pageRef { dict["pageRef"] = pageRef }
        if weight != 0 { dict["weight"] = weight }
        if let identifier = identifier { dict["identifier"] = identifier }
        if let parent = parent { dict["parent"] = parent }
        if let title = title { dict["title"] = title }
        return dict
    }
}

extension HugoMenuItem {
    /// Which of the two mutually-exclusive link fields is being edited
    /// (CONFIG-SCHEMA-SPEC §3.4: `url` XOR `pageRef`).
    enum LinkType {
        case url
        case pageRef
    }

    /// Enforces `url` XOR `pageRef`. Setting a **non-empty** value for one
    /// field clears the other (Hugo only honors one). Setting an empty/nil
    /// value only clears the field being edited — blanking an unused field
    /// must never wipe out a value already set on its sibling.
    ///
    /// Pure: returns a new item, never mutates `item`. Used by
    /// `ConfigMenusTab`'s per-item link editor.
    static func settingLink(_ item: HugoMenuItem, type: LinkType, value: String?) -> HugoMenuItem {
        var updated = item
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nonEmpty = (trimmed?.isEmpty ?? true) ? nil : trimmed
        switch type {
        case .url:
            updated.url = nonEmpty
            if nonEmpty != nil { updated.pageRef = nil }
        case .pageRef:
            updated.pageRef = nonEmpty
            if nonEmpty != nil { updated.url = nil }
        }
        return updated
    }

    /// Reassigns `weight` in steps of 10 (10, 20, 30, …) following `items`'
    /// order — the effect of a drag-reorder in the Menus tab
    /// (CONFIG-SCHEMA-SPEC §3.4). Pure: returns a new array, never mutates
    /// `items`. Stable (returns `[]`/single-item unchanged in shape) for
    /// empty/single-item input.
    static func reweighted(_ items: [HugoMenuItem]) -> [HugoMenuItem] {
        items.enumerated().map { index, item in
            var copy = item
            copy.weight = (index + 1) * 10
            return copy
        }
    }
}

private extension HugoConfig {
    /// Establishes the observation dependency on `store.version` before
    /// running `body`, so every computed accessor above depends on the
    /// store's single observable signal (`store.root` itself is
    /// `@ObservationIgnored` and must never be read directly by a getter —
    /// CLAUDE.md's Per-Keystroke Invalidation Contract / CONFIG-SCHEMA-SPEC
    /// §2.8). A method (not a free function) so `_ = store.version` is
    /// spelled once and can't be forgotten on a new accessor.
    func tracked<T>(_ body: () -> T) -> T {
        _ = store.version
        return body()
    }
}
