import Foundation

/// Tab/section placement for a `ConfigSettingSpec`. `.menus` intentionally
/// has zero entries in `ConfigSchema.all` — the Menus tab stays a bespoke
/// typed materialization (`HugoConfig.menus: [String: [HugoMenuItem]]`),
/// never routed through the generic schema/store renderer (CONFIG-SCHEMA-SPEC
/// §2.9, §3.4). `ConfigSchemaTests` documents and enforces this exception.
enum ConfigGroup: String, CaseIterable, Sendable {
    case essentials, contentBuild, urlsTaxonomies, menus, markup, integrations, advanced
}

/// The shape a setting's value takes, and therefore which control renders it
/// (`ConfigFieldView`, a later phase). CONFIG-SCHEMA-SPEC §2.3.
enum ConfigValueType: Sendable {
    case bool
    case string
    case int
    case double
    case duration                      // string like "60s"; bare int = seconds
    case stringArray                   // token field
    case stringMap                     // flat [String: String] (taxonomies-like)
    case choice([String])              // exclusive enum, Picker
    case boolOrEnum([String])          // lineNos
    case stringOrStringArray           // theme, staticDir
    case boolOrSectionMap              // uglyURLs
    case dictionary                    // recursive editor subtree (params, author, social)
    case rawOnly                       // shown read-only + "Edit in Raw"
}

/// A setting's default. Three cases because two Hugo defaults are sentinels whose *number*
/// must never be shown as something to copy, only their meaning (CONFIG-SCHEMA-SPEC §2.3).
/// `@unchecked Sendable`: the payload is always a Bool/String/Int/Double/array, but Hugo's
/// config values are dynamically typed so it can't be proved to the compiler.
enum ConfigDefault: @unchecked Sendable {
    case value(Any)
    case none
    case sentinel(Any, meaning: String)
}

/// A single deprecated-key migration path (CONFIG-SCHEMA-SPEC §2.5,
/// mechanism 1: "spec-attached deprecation"). The key stays in the schema —
/// it still round-trips — but its field renders a badge/message, plus an
/// optional one-click "Rename key" affordance when `replacementKey` is set.
struct ConfigDeprecation: Sendable {
    let since: String
    let message: String
    let replacementKey: String?
}

/// One row of the config schema table (CONFIG-SCHEMA-SPEC §2.3, final shape).
struct ConfigSettingSpec: Identifiable, Sendable {
    var id: String { key }
    let key: String
    let type: ConfigValueType
    let defaultValue: ConfigDefault
    let label: String
    let help: String
    let group: ConfigGroup
    let validator: ConfigValidator?
    let deprecation: ConfigDeprecation?
    /// `.bool` entries only: the toggle displays and writes the logical NOT of the stored
    /// value. For keys phrased as "disable X" that should read as "X" and show ON when X
    /// is active. The stored key and type never change - only the toggle's direction.
    var invertedBoolLabel: Bool = false
}

// MARK: - Entry builders
//
// Thin constructors so the ~220-row table below reads as data, not
// boilerplate. Each mirrors one `ConfigValueType` shape.

private func entry(
    _ key: String,
    _ type: ConfigValueType,
    _ defaultValue: ConfigDefault,
    _ label: String,
    _ help: String,
    _ group: ConfigGroup,
    validator: ConfigValidator? = nil,
    deprecation: ConfigDeprecation? = nil,
    invertedBoolLabel: Bool = false
) -> ConfigSettingSpec {
    ConfigSettingSpec(key: key, type: type, defaultValue: defaultValue, label: label, help: help, group: group, validator: validator, deprecation: deprecation, invertedBoolLabel: invertedBoolLabel)
}

private func boolEntry(
    _ key: String, _ def: Bool, _ label: String, _ help: String, _ group: ConfigGroup,
    deprecation: ConfigDeprecation? = nil, invertedBoolLabel: Bool = false
) -> ConfigSettingSpec {
    entry(key, .bool, .value(def), label, help, group, deprecation: deprecation, invertedBoolLabel: invertedBoolLabel)
}

private func stringEntry(
    _ key: String, _ def: String?, _ label: String, _ help: String, _ group: ConfigGroup,
    validator: ConfigValidator? = nil, deprecation: ConfigDeprecation? = nil
) -> ConfigSettingSpec {
    entry(key, .string, def.map(ConfigDefault.value) ?? .none, label, help, group, validator: validator, deprecation: deprecation)
}

private func intEntry(
    _ key: String, _ def: Int, _ label: String, _ help: String, _ group: ConfigGroup,
    validator: ConfigValidator? = nil
) -> ConfigSettingSpec {
    entry(key, .int, .value(def), label, help, group, validator: validator)
}

private func arrayEntry(
    _ key: String, _ def: [String], _ label: String, _ help: String, _ group: ConfigGroup,
    validator: ConfigValidator? = nil
) -> ConfigSettingSpec {
    entry(key, .stringArray, .value(def), label, help, group, validator: validator)
}

private func stringMapEntry(
    _ key: String, _ def: [String: String], _ label: String, _ help: String, _ group: ConfigGroup,
    validator: ConfigValidator? = nil
) -> ConfigSettingSpec {
    entry(key, .stringMap, .value(def), label, help, group, validator: validator)
}

/// `.choice` entries default to `memberOf(options)` unless a caller overrides.
private func choiceEntry(
    _ key: String, _ options: [String], _ def: String, _ label: String, _ help: String, _ group: ConfigGroup,
    validator: ConfigValidator? = nil
) -> ConfigSettingSpec {
    entry(key, .choice(options), .value(def), label, help, group, validator: validator ?? ConfigValidators.memberOf(options))
}

private func rawOnlyEntry(_ key: String, _ label: String, _ help: String) -> ConfigSettingSpec {
    entry(key, .rawOnly, .none, label, help, .advanced)
}

private func deprecatedBoolEntry(
    _ key: String, _ def: Bool, _ label: String, _ help: String, _ group: ConfigGroup,
    since: String, message: String, replacement: String?
) -> ConfigSettingSpec {
    boolEntry(key, def, label, help, group, deprecation: ConfigDeprecation(since: since, message: message, replacementKey: replacement))
}

private func deprecatedStringEntry(
    _ key: String, _ def: String?, _ label: String, _ help: String, _ group: ConfigGroup,
    since: String, message: String, replacement: String?
) -> ConfigSettingSpec {
    stringEntry(key, def, label, help, group, deprecation: ConfigDeprecation(since: since, message: message, replacementKey: replacement))
}

private func deprecatedArrayEntry(
    _ key: String, _ def: [String], _ label: String, _ help: String, _ group: ConfigGroup,
    since: String, message: String, replacement: String?
) -> ConfigSettingSpec {
    entry(key, .stringArray, .value(def), label, help, group, deprecation: ConfigDeprecation(since: since, message: message, replacementKey: replacement))
}

// MARK: - §3.1 Essentials

private let essentialsEntries: [ConfigSettingSpec] = [
    stringEntry("baseURL", "", "Base URL", "Absolute URL Hugo prepends to all relative URLs it generates.", .essentials, validator: ConfigValidators.absoluteURL),
    stringEntry("title", "", "Title", "Site title, read by themes for <title>/headers and RSS feeds.", .essentials),
    entry("theme", .stringOrStringArray, .none, "Theme", "Theme name(s), read from the themes/ directory (or Hugo Modules).", .essentials, validator: ConfigValidators.themeExists),
    stringEntry("copyright", "", "Copyright", "Copyright notice, often shown in theme footers.", .essentials),
    stringEntry("locale", "", "Locale", "BCP 47 language/locale tag (e.g. en-US). Supersedes languageCode since Hugo v0.158.0.", .essentials, validator: ConfigValidators.bcp47ish),
    stringEntry(
        "languageCode", "", "Language Code",
        "Legacy language tag; Hugo copies it into locale in memory and ignores it if locale is also set.",
        .essentials, validator: ConfigValidators.bcp47ish,
        deprecation: ConfigDeprecation(since: "0.158.0", message: "Use locale instead.", replacementKey: "locale")
    ),
    stringEntry("defaultContentLanguage", "en", "Default Content Language", "Language used for content with no language suffix, and the default in multilingual sites.", .essentials, validator: ConfigValidators.bcp47ish),
    // `.choice` rather than a bespoke row: the identifier list is >15 entries, so
    // `ConfigFieldView`'s searchable-choice control kicks in automatically.
    entry(
        "timeZone", .choice(ConfigSchema.timeZoneIdentifiers), .value(""), "Time Zone",
        "IANA time zone identifier used to interpret dates that have no explicit offset.",
        .essentials, validator: ConfigValidators.timezone
    )
]

// MARK: - §3.2 Content & Build

private let contentBuildEntries: [ConfigSettingSpec] = [
    boolEntry("buildDrafts", false, "Build Drafts", "Include content with draft: true in the build.", .contentBuild),
    boolEntry("buildFuture", false, "Build Future", "Include content dated after the current build time.", .contentBuild),
    boolEntry("buildExpired", false, "Build Expired", "Include content whose expiryDate has already passed.", .contentBuild),
    boolEntry("enableGitInfo", false, "Enable Git Info", "Attach last-modified and author metadata from Git history to each page.", .contentBuild),
    boolEntry("enableEmoji", false, "Enable Emoji", "Render :emoji-name: shortcodes in content as Unicode emoji.", .contentBuild),
    boolEntry("hasCJKLanguage", false, "Has CJK Language", "Treat CJK characters as individual words for summaries and word counts.", .contentBuild),
    intEntry("summaryLength", 70, "Summary Length", "Word count of auto-generated summaries when content has no <!--more--> marker.", .contentBuild, validator: ConfigValidators.intRange(min: 1)),
    arrayEntry("mainSections", [], "Main Sections", "Sections treated as the site's primary content; Hugo guesses the largest section when unset.", .contentBuild),
    choiceEntry("titleCaseStyle", ConfigSchema.titleCaseStyles, "ap", "Title Case Style", "Casing style applied to automatically-generated titles (e.g. section/taxonomy list titles).", .contentBuild),
    boolEntry("pluralizeListTitles", true, "Pluralize List Titles", "Pluralize automatically-generated section/taxonomy list titles.", .contentBuild),
    boolEntry("capitalizeListTitles", true, "Capitalize List Titles", "Capitalize automatically-generated list titles.", .contentBuild),
    entry("timeout", .duration, .value("60s"), "Timeout", "Max time a single build operation may take; a bare integer is interpreted as seconds.", .contentBuild, validator: ConfigValidators.duration),
    arrayEntry("disableKinds", [], "Disable Kinds", "Page kinds to skip building entirely (e.g. taxonomy, term, RSS).", .contentBuild, validator: ConfigValidators.kindsList),
    stringEntry("environment", "production", "Environment", "Build environment name; production for hugo build, development for hugo server.", .contentBuild)
]

// MARK: - §3.3 URLs & Taxonomies

private let urlsTaxonomiesEntries: [ConfigSettingSpec] = [
    // `permalinks` keeps its bespoke editor entirely — see the Phase 1b
    // ambiguity note in ConfigSchemaTests / the execution log for why it has
    // no ConfigSettingSpec entry here, unlike `taxonomies`.
    stringMapEntry("taxonomies", ["category": "categories", "tag": "tags"], "Taxonomies", "Map of taxonomy singular name to plural name (e.g. tag \u{2192} tags).", .urlsTaxonomies, validator: ConfigValidators.taxonomyPair),
    intEntry("pagination.pagerSize", 10, "Pager Size", "Number of items per page on paginated list pages.", .urlsTaxonomies, validator: ConfigValidators.intRange(min: 1)),
    stringEntry("pagination.path", "page", "Pagination Path", "URL path segment used for paginated pages (e.g. /page/2/).", .urlsTaxonomies),
    boolEntry("pagination.disableAliases", false, "Disable Pagination Aliases", "Skip writing alias redirect pages for a list's first page.", .urlsTaxonomies),
    boolEntry("canonifyURLs", false, "Canonify URLs", "Rewrite relative URLs found in content to absolute URLs at build time.", .urlsTaxonomies),
    boolEntry("relativeURLs", false, "Relative URLs", "Rewrite generated URLs relative to the current page instead of the site root.", .urlsTaxonomies),
    entry("uglyURLs", .boolOrSectionMap, .value(false), "Ugly URLs", "Use file.html URLs instead of pretty file/ URLs; can also be a per-section map.", .urlsTaxonomies),
    boolEntry("disablePathToLower", false, "Disable Path To Lower", "Preserve the case of generated URL paths instead of lowercasing them.", .urlsTaxonomies),
    boolEntry("removePathAccents", false, "Remove Path Accents", "Strip accented characters from generated URL paths.", .urlsTaxonomies),
    boolEntry("disableAliases", false, "Disable Aliases", "Stop Hugo from writing alias redirect pages.", .urlsTaxonomies),
    boolEntry("enableRobotsTXT", false, "Enable robots.txt", "Generate a robots.txt file from the robots.txt template.", .urlsTaxonomies),
    stringEntry("sectionPagesMenu", "", "Section Pages Menu", "Name of an auto-generated menu listing the site's top-level sections.", .urlsTaxonomies)
]

// MARK: - §3.5 Markup

private let markupEntries: [ConfigSettingSpec] = [
    choiceEntry("markup.defaultMarkdownHandler", ["goldmark", "asciidocext", "org", "pandoc", "rst"], "goldmark", "Markdown Handler", "Content renderer for Markdown files; only goldmark needs no external tool.", .markup),
    boolEntry("markup.goldmark.renderer.unsafe", false, "Allow Raw HTML", "Permit raw HTML and unsafe links to pass through in rendered Markdown.", .markup),
    boolEntry("markup.goldmark.renderer.hardWraps", false, "Hard Line Wraps", "Render a single newline within a paragraph as <br>.", .markup),
    boolEntry("markup.goldmark.extensions.typographer.disable", false, "Smart Punctuation", "Disables automatic curly quotes/dashes/ellipses when true (inverted: false keeps Hugo's default smart punctuation on).", .markup, invertedBoolLabel: true),
    boolEntry("markup.goldmark.extensions.table", true, "Tables", "Enable GitHub-style pipe tables in Markdown.", .markup),
    boolEntry("markup.goldmark.extensions.strikethrough", true, "Strikethrough", "Enable ~~strikethrough~~ syntax.", .markup),
    boolEntry("markup.goldmark.extensions.linkify", true, "Auto-link URLs", "Automatically turn bare URLs and email addresses into links.", .markup),
    choiceEntry("markup.goldmark.extensions.linkifyProtocol", ["http", "https"], "https", "Linkify Protocol", "Protocol assumed when auto-linking bare www/domain text with no scheme.", .markup),
    boolEntry("markup.goldmark.extensions.taskList", true, "Task Lists", "Enable - [ ] checkbox task-list syntax.", .markup),
    boolEntry("markup.goldmark.extensions.definitionList", true, "Definition Lists", "Enable Term/: Description definition-list syntax.", .markup),
    boolEntry("markup.goldmark.extensions.footnote.enable", true, "Footnotes", "Enable [^1] footnote reference syntax.", .markup),
    boolEntry("markup.goldmark.parser.autoHeadingID", true, "Auto Heading IDs", "Automatically generate id attributes for headings.", .markup),
    choiceEntry("markup.goldmark.parser.autoIDType", ConfigSchema.autoIDTypes, "github", "Heading ID Style", "Algorithm used to slugify automatically-generated heading IDs.", .markup),
    boolEntry("markup.goldmark.parser.attribute.title", true, "Title Attributes", "Allow {#id .class} attribute syntax after headings and paragraphs.", .markup),
    boolEntry("markup.goldmark.parser.attribute.block", false, "Block Attributes", "Allow attribute syntax on block-level elements (fenced code, blockquotes, lists).", .markup),
    choiceEntry("markup.highlight.style", ConfigSchema.chromaStyles, "monokai", "Syntax Highlight Style", "Chroma color theme applied to syntax-highlighted code blocks.", .markup),
    boolEntry("markup.highlight.codeFences", true, "Code Fences", "Apply syntax highlighting to ``` fenced code blocks.", .markup),
    entry("markup.highlight.lineNos", .boolOrEnum(["inline", "table"]), .value(false), "Line Numbers", "Show line numbers on highlighted code, either inline or as a separate table column.", .markup),
    boolEntry("markup.highlight.lineNumbersInTable", true, "Line Numbers In Table", "Render line numbers as a table column rather than an inline gutter.", .markup),
    intEntry("markup.highlight.lineNoStart", 1, "Line Number Start", "First line number shown when line numbers are enabled.", .markup, validator: ConfigValidators.intRange(min: 1)),
    boolEntry("markup.highlight.noClasses", true, "Inline CSS", "Emit inline styles instead of CSS classes, so no external stylesheet is needed.", .markup),
    intEntry("markup.highlight.tabWidth", 4, "Tab Width", "Number of spaces a tab character expands to in highlighted code.", .markup, validator: ConfigValidators.intRange(min: 1, max: 16)),
    boolEntry("markup.highlight.guessSyntax", false, "Guess Syntax", "Attempt to detect the language of fenced code blocks with no language hint.", .markup),
    intEntry("markup.tableOfContents.startLevel", 2, "TOC Start Level", "Shallowest heading level (h1 = 1) included in the table of contents.", .markup, validator: ConfigValidators.intRange(min: 1, max: 6)),
    intEntry("markup.tableOfContents.endLevel", 3, "TOC End Level", "Deepest heading level included in the table of contents; -1 includes all levels.", .markup, validator: ConfigValidators.intRange(min: -1, max: 6)),
    boolEntry("markup.tableOfContents.ordered", false, "Ordered List", "Render the table of contents as an ordered (numbered) list.", .markup)
]

/// Schema-known but "Advanced list only" (§3.5's closing paragraph): shown in
/// the All Settings search list, not on the Markup tab itself.
private let markupAdvancedEntries: [ConfigSettingSpec] = [
    boolEntry("markup.goldmark.renderer.xhtml", false, "XHTML Output", "Render self-closing XHTML-style tags instead of HTML5.", .advanced),
    stringEntry("markup.highlight.wrapperClass", "highlight", "Wrapper Class", "CSS class (and element) wrapping highlighted code blocks.", .advanced),
    boolEntry("markup.goldmark.extensions.cjk.enable", false, "CJK Extensions", "Enable CJK-aware line-break and spacing handling.", .advanced),
    boolEntry("markup.goldmark.extensions.cjk.eastAsianLineBreaks", false, "East Asian Line Breaks", "Remove soft line breaks between adjacent East Asian characters.", .advanced),
    boolEntry("markup.goldmark.extensions.cjk.eastAsianLineBreaksSegment", false, "East Asian Line Break Segmentation", "Use segmented line-break rules for East Asian text.", .advanced),
    boolEntry("markup.goldmark.extensions.cjk.escapedSpace", false, "Escaped Space", "Preserve a backslash-escaped space between CJK characters.", .advanced),
    boolEntry("markup.goldmark.extensions.extras.delete.enable", false, "Delete Extension", "Enable ~~del~~-style delete syntax from goldmark's extras extension.", .advanced),
    boolEntry("markup.goldmark.extensions.extras.insert.enable", false, "Insert Extension", "Enable ++ins++ insert syntax.", .advanced),
    boolEntry("markup.goldmark.extensions.extras.mark.enable", false, "Mark Extension", "Enable ==mark== highlighted-text syntax.", .advanced),
    boolEntry("markup.goldmark.extensions.extras.subscript.enable", false, "Subscript Extension", "Enable ~sub~ subscript syntax.", .advanced),
    boolEntry("markup.goldmark.extensions.extras.superscript.enable", false, "Superscript Extension", "Enable ^sup^ superscript syntax.", .advanced),
    boolEntry("markup.goldmark.extensions.passthrough.enable", false, "Passthrough Extension", "Enable raw passthrough of custom delimited spans (e.g. for math).", .advanced),
    arrayEntry("markup.goldmark.extensions.passthrough.delimiters.block", [], "Passthrough Block Delimiters", "Delimiter pairs treated as passthrough at the block level.", .advanced),
    arrayEntry("markup.goldmark.extensions.passthrough.delimiters.inline", [], "Passthrough Inline Delimiters", "Delimiter pairs treated as passthrough inline.", .advanced),
    choiceEntry("markup.goldmark.renderHooks.image.useEmbedded", ConfigSchema.renderHooksUseEmbedded, "auto", "Image Render Hook", "When to use Hugo's embedded image render hook versus a theme-provided one.", .advanced),
    choiceEntry("markup.goldmark.renderHooks.link.useEmbedded", ConfigSchema.renderHooksUseEmbedded, "auto", "Link Render Hook", "When to use Hugo's embedded link render hook versus a theme-provided one.", .advanced),
    boolEntry("markup.goldmark.parser.wrapStandAloneImageWithinParagraph", true, "Wrap Standalone Images", "Wrap an image that is the sole content of a paragraph in a <p>.", .advanced),
    boolEntry("markup.goldmark.parser.autoDefinitionTermID", false, "Auto Definition Term ID", "Automatically generate id attributes for definition-list terms.", .advanced),
    stringEntry("markup.goldmark.extensions.typographer.apostrophe", "&rsquo;", "Apostrophe", "Replacement for straight apostrophes (').", .advanced),
    stringEntry("markup.goldmark.extensions.typographer.ellipsis", "&hellip;", "Ellipsis", "Replacement for three dots (...).", .advanced),
    stringEntry("markup.goldmark.extensions.typographer.emDash", "&mdash;", "Em Dash", "Replacement for an em dash (---).", .advanced),
    stringEntry("markup.goldmark.extensions.typographer.enDash", "&ndash;", "En Dash", "Replacement for an en dash (--).", .advanced),
    stringEntry("markup.goldmark.extensions.typographer.leftAngleQuote", "&laquo;", "Left Angle Quote", "Replacement for a left angle quote (<<).", .advanced),
    stringEntry("markup.goldmark.extensions.typographer.leftDoubleQuote", "&ldquo;", "Left Double Quote", "Replacement for an opening double quote.", .advanced),
    stringEntry("markup.goldmark.extensions.typographer.leftSingleQuote", "&lsquo;", "Left Single Quote", "Replacement for an opening single quote.", .advanced),
    stringEntry("markup.goldmark.extensions.typographer.rightAngleQuote", "&raquo;", "Right Angle Quote", "Replacement for a right angle quote (>>).", .advanced),
    stringEntry("markup.goldmark.extensions.typographer.rightDoubleQuote", "&rdquo;", "Right Double Quote", "Replacement for a closing double quote.", .advanced),
    stringEntry("markup.goldmark.extensions.typographer.rightSingleQuote", "&rsquo;", "Right Single Quote", "Replacement for a closing single quote.", .advanced),
    boolEntry("markup.goldmark.extensions.footnote.enableAutoIDPrefix", true, "Footnote Auto ID Prefix", "Prefix footnote IDs with the page's content path to keep them unique across pages.", .advanced),
    stringEntry("markup.goldmark.extensions.footnote.backlinkHTML", "<a href=\"#fnref:%s\" class=\"footnote-backref\" role=\"doc-backlink\">&#x21a9;&#xfe0e;</a>", "Footnote Backlink HTML", "HTML template for the footnote-to-reference backlink.", .advanced),
    stringEntry("markup.asciidocExt.backend", "html5", "AsciiDoc Backend", "Output backend passed to the external asciidoctor binary.", .advanced),
    stringEntry("markup.asciidocExt.failureLevel", "fatal", "AsciiDoc Failure Level", "Log level at which asciidoctor exits non-zero.", .advanced),
    boolEntry("markup.asciidocExt.noHeaderOrFooter", true, "AsciiDoc No Header/Footer", "Render an embeddable fragment instead of a full HTML document.", .advanced),
    boolEntry("markup.asciidocExt.preserveTOC", false, "AsciiDoc Preserve TOC", "Keep asciidoctor's own table of contents instead of Hugo's.", .advanced),
    stringEntry("markup.asciidocExt.safeMode", "unsafe", "AsciiDoc Safe Mode", "asciidoctor safe mode: unsafe, safe, server, or secure.", .advanced),
    boolEntry("markup.asciidocExt.sectionNumbers", false, "AsciiDoc Section Numbers", "Number section headings.", .advanced),
    boolEntry("markup.asciidocExt.trace", false, "AsciiDoc Trace", "Include asciidoctor backtraces in error output.", .advanced),
    boolEntry("markup.asciidocExt.workingFolderCurrent", false, "AsciiDoc Working Folder Current", "Run asciidoctor with its working directory set to the content file's folder.", .advanced),
    boolEntry("markup.rst.unsafe", false, "RST Unsafe", "Allow raw directives in reStructuredText content.", .advanced)
]

// MARK: - §3.6 Integrations

private let integrationsEntries: [ConfigSettingSpec] = [
    stringEntry("services.googleAnalytics.ID", "", "Google Analytics ID", "Measurement/tracking ID for Google Analytics (e.g. G-XXXXXXX).", .integrations),
    boolEntry("privacy.googleAnalytics.disable", false, "Disable Google Analytics", "Omit the Google Analytics template output entirely.", .integrations),
    boolEntry("privacy.googleAnalytics.respectDoNotTrack", true, "Respect Do Not Track", "Skip tracking when the visitor's browser sends Do Not Track.", .integrations),
    stringEntry("services.disqus.shortname", "", "Disqus Shortname", "Site shortname registered with Disqus.", .integrations),
    boolEntry("privacy.disqus.disable", false, "Disable Disqus", "Omit the Disqus comments template output.", .integrations),
    boolEntry("services.x.disableInlineCSS", false, "Disable X Inline CSS", "Skip the inline styles Hugo adds to embedded X (Twitter) posts.", .integrations),
    boolEntry("privacy.x.disable", false, "Disable X Embeds", "Omit the X (Twitter) embed shortcode output.", .integrations),
    boolEntry("privacy.x.enableDNT", false, "X Do Not Track", "Instruct embedded X posts to honor Do Not Track.", .integrations),
    boolEntry("privacy.x.simple", false, "X Simple Embeds", "Render X posts without loading X's JavaScript widget.", .integrations),
    boolEntry("privacy.youtube.disable", false, "Disable YouTube Embeds", "Omit the YouTube embed shortcode output.", .integrations),
    boolEntry("privacy.youtube.privacyEnhanced", false, "YouTube Privacy-Enhanced Mode", "Use youtube-nocookie.com for embedded videos.", .integrations),
    boolEntry("privacy.vimeo.disable", false, "Disable Vimeo Embeds", "Omit the Vimeo embed shortcode output.", .integrations),
    boolEntry("privacy.vimeo.enableDNT", false, "Vimeo Do Not Track", "Instruct the embedded Vimeo player to honor Do Not Track.", .integrations),
    boolEntry("privacy.vimeo.simple", false, "Vimeo Simple Embeds", "Render Vimeo embeds without the JavaScript player.", .integrations),
    boolEntry("privacy.instagram.disable", false, "Disable Instagram Embeds", "Omit the Instagram embed shortcode output.", .integrations),
    boolEntry("privacy.instagram.simple", false, "Instagram Simple Embeds", "Render Instagram embeds without loading Instagram's JavaScript.", .integrations),
    entry("services.rss.limit", .int, .sentinel(-1, meaning: "unlimited"), "RSS Item Limit", "Maximum number of items in generated RSS feeds.", .integrations, validator: ConfigValidators.intRange(min: -1)),
    choiceEntry("sitemap.changeFreq", ConfigSchema.sitemapChangeFreqs, "", "Sitemap Change Frequency", "changefreq hint written into sitemap.xml entries; empty omits it.", .integrations, validator: ConfigValidators.changeFreq),
    entry("sitemap.priority", .double, .sentinel(-1.0, meaning: "omitted from sitemap"), "Sitemap Priority", "priority hint (0.0-1.0) written into sitemap.xml entries.", .integrations, validator: ConfigValidators.priorityRange),
    stringEntry("sitemap.filename", "sitemap.xml", "Sitemap Filename", "Filename of the generated sitemap.", .integrations),
    boolEntry("sitemap.disable", false, "Disable Sitemap", "Skip generating the sitemap entirely.", .integrations),
    arrayEntry("outputs.home", ["html", "rss"], "Home Output Formats", "Output formats rendered for the home page.", .integrations, validator: ConfigValidators.outputFormatsKnown),
    arrayEntry("outputs.page", ["html"], "Page Output Formats", "Output formats rendered for regular pages.", .integrations, validator: ConfigValidators.outputFormatsKnown),
    arrayEntry("outputs.section", ["html", "rss"], "Section Output Formats", "Output formats rendered for section list pages.", .integrations, validator: ConfigValidators.outputFormatsKnown),
    arrayEntry("outputs.taxonomy", ["html", "rss"], "Taxonomy Output Formats", "Output formats rendered for taxonomy list pages.", .integrations, validator: ConfigValidators.outputFormatsKnown),
    arrayEntry("outputs.term", ["html", "rss"], "Term Output Formats", "Output formats rendered for taxonomy term pages.", .integrations, validator: ConfigValidators.outputFormatsKnown),
    // Twitter → X rename (v0.141) — mechanism-1 deprecations, co-located with their replacements.
    deprecatedBoolEntry("privacy.twitter.disable", false, "Disable Twitter Embeds (legacy)", "Legacy key from before the Twitter → X rename.", .integrations, since: "0.141.0", message: "Renamed to privacy.x.disable.", replacement: "privacy.x.disable"),
    deprecatedBoolEntry("privacy.twitter.enableDNT", false, "Twitter Do Not Track (legacy)", "Legacy key from before the Twitter → X rename.", .integrations, since: "0.141.0", message: "Renamed to privacy.x.enableDNT.", replacement: "privacy.x.enableDNT"),
    deprecatedBoolEntry("privacy.twitter.simple", false, "Twitter Simple Embeds (legacy)", "Legacy key from before the Twitter → X rename.", .integrations, since: "0.141.0", message: "Renamed to privacy.x.simple.", replacement: "privacy.x.simple"),
    deprecatedBoolEntry("services.twitter.disableInlineCSS", false, "Disable Twitter Inline CSS (legacy)", "Legacy key from before the Twitter → X rename.", .integrations, since: "0.141.0", message: "Renamed to services.x.disableInlineCSS.", replacement: "services.x.disableInlineCSS")
]

// MARK: - §3.7 Advanced — root keys (b)

private let advancedRootEntries: [ConfigSettingSpec] = [
    boolEntry("defaultContentLanguageInSubdir", false, "Default Language In Subdir", "Serve the default language under its own /xx/ subdirectory, like other languages.", .advanced),
    stringEntry("defaultContentRole", nil, "Default Content Role", "Default role assigned to content with no role dimension set.", .advanced),
    boolEntry("defaultContentRoleInSubdir", false, "Default Role In Subdir", "Serve the default content role under its own subdirectory.", .advanced),
    stringEntry("defaultContentVersion", nil, "Default Content Version", "Default version assigned to content with no version dimension set.", .advanced),
    boolEntry("defaultContentVersionInSubdir", false, "Default Version In Subdir", "Serve the default content version under its own subdirectory.", .advanced),
    stringEntry("defaultOutputFormat", "html", "Default Output Format", "Output format used when a template reference doesn't name one.", .advanced),
    boolEntry("disableDefaultLanguageRedirect", false, "Disable Default Language Redirect", "Skip auto-redirecting / to the default language's home page.", .advanced),
    boolEntry("disableDefaultSiteRedirect", false, "Disable Default Site Redirect", "Skip auto-redirecting / to the default site dimension (role/version).", .advanced),
    boolEntry("disableHugoGeneratorInject", false, "Disable Generator Tag", "Omit the <meta name=\"generator\" content=\"Hugo …\"> tag Hugo injects.", .advanced),
    arrayEntry("disableLanguages", [], "Disable Languages", "Language codes to exclude from the build entirely.", .advanced),
    boolEntry("disableLiveReload", false, "Disable Live Reload", "Turn off the LiveReload script hugo server injects.", .advanced),
    arrayEntry("renderSegments", [], "Render Segments", "Named subsets of the site to build, for partial/segmented builds.", .advanced),
    boolEntry("enableMissingTranslationPlaceholders", false, "Show Missing Translation Placeholders", "Render [i18n] <key> placeholders for missing translation strings instead of empty output.", .advanced),
    boolEntry("templateMetrics", false, "Template Metrics", "Print template execution/render time metrics after a build.", .advanced),
    boolEntry("templateMetricsHints", false, "Template Metrics Hints", "Include optimization hints alongside template metrics.", .advanced),
    boolEntry("noBuildLock", false, "No Build Lock", "Skip the build lock file, allowing concurrent Hugo processes against the same site.", .advanced),
    boolEntry("ignoreCache", false, "Ignore Cache", "Bypass Hugo's file caches for this build.", .advanced),
    arrayEntry("ignoreLogs", [], "Ignore Log IDs", "Log message IDs to suppress from build output.", .advanced),
    stringEntry("ignoreVendorPaths", "", "Ignore Vendor Paths", "Glob of vendored module paths to exclude from the build.", .advanced),
    boolEntry("panicOnWarning", false, "Panic On Warning", "Abort the build immediately on the first warning.", .advanced),
    boolEntry("printI18nWarnings", false, "Print i18n Warnings", "Log a warning for each missing translation string.", .advanced),
    boolEntry("printPathWarnings", false, "Print Path Warnings", "Log a warning for duplicate target output paths.", .advanced),
    boolEntry("printUnusedTemplates", false, "Print Unused Templates", "Log templates that were never invoked during the build.", .advanced),
    choiceEntry("refLinksErrorLevel", ["ERROR", "WARNING"], "ERROR", "Ref Link Error Level", "Log level used when a ref/relref shortcode target can't be resolved.", .advanced),
    stringEntry("refLinksNotFoundURL", "", "Ref Links Not-Found URL", "Fallback URL used when a ref/relref target can't be resolved.", .advanced),
    stringEntry("newContentEditor", "", "New Content Editor", "Editor command hugo new opens the newly-created file in.", .advanced),
    boolEntry("noChmod", false, "No Chmod", "Skip matching permission bits of generated files to their source.", .advanced),
    boolEntry("noTimes", false, "No Times", "Skip setting modification times on generated files.", .advanced),
    boolEntry("cleanDestinationDir", false, "Clean Destination Dir", "Remove files in the output directory with no corresponding source file.", .advanced),
    choiceEntry("page.nextPrevSortOrder", ConfigSchema.pageSortOrders, "desc", "Next/Prev Sort Order", "Sort order used when computing a page's site-wide Next/Prev neighbors.", .advanced),
    choiceEntry("page.nextPrevInSectionSortOrder", ConfigSchema.pageSortOrders, "desc", "Next/Prev In-Section Sort Order", "Sort order used when computing a page's in-section Next/Prev neighbors.", .advanced),
    intEntry("related.threshold", 80, "Related Threshold", "Minimum match score (0-100) for a page to count as related.", .advanced, validator: ConfigValidators.intRange(min: 0, max: 100)),
    boolEntry("related.includeNewer", false, "Related Include Newer", "Allow related content that is newer than the current page.", .advanced),
    boolEntry("related.toLower", false, "Related Case-Fold", "Lowercase indexed terms before comparing related content.", .advanced),
    boolEntry("minify.minifyOutput", false, "Minify Output", "Minify all generated HTML/CSS/JS/etc. output.", .advanced),
    boolEntry("minify.disableHTML", false, "Disable HTML Minify", "Skip HTML minification even when minifyOutput is on.", .advanced),
    boolEntry("minify.disableCSS", false, "Disable CSS Minify", "Skip CSS minification even when minifyOutput is on.", .advanced),
    boolEntry("minify.disableJS", false, "Disable JS Minify", "Skip JS minification even when minifyOutput is on.", .advanced),
    boolEntry("minify.disableJSON", false, "Disable JSON Minify", "Skip JSON minification even when minifyOutput is on.", .advanced),
    boolEntry("minify.disableSVG", false, "Disable SVG Minify", "Skip SVG minification even when minifyOutput is on.", .advanced),
    boolEntry("minify.disableXML", false, "Disable XML Minify", "Skip XML minification even when minifyOutput is on.", .advanced),
    intEntry("imaging.quality", 75, "Image Quality", "JPEG/WebP encoding quality (1-100) applied to processed images.", .advanced, validator: ConfigValidators.intRange(min: 1, max: 100)),
    stringEntry("imaging.resampleFilter", "box", "Resample Filter", "Resampling filter used when resizing images.", .advanced),
    stringEntry("imaging.hint", "photo", "Imaging Hint", "Encoder hint (photo/picture/drawing/icon) used by some image encoders.", .advanced),
    stringEntry("imaging.anchor", "smart", "Imaging Anchor", "Anchor point used when cropping images (e.g. smart, center, topLeft).", .advanced),
    stringEntry("imaging.bgColor", "#ffffff", "Image Background Color", "Background color used when flattening transparency (e.g. to JPEG).", .advanced, validator: ConfigValidators.hexColor)
]

// MARK: - §3.7 Advanced — directory overrides (b)

private let directoryOverrideEntries: [ConfigSettingSpec] = [
    stringEntry("archetypeDir", "archetypes", "Archetype Dir", "Directory of content templates used by hugo new.", .advanced),
    stringEntry("assetDir", "assets", "Asset Dir", "Directory of files processed by Hugo Pipes (SCSS, JS bundling, image processing).", .advanced),
    stringEntry("cacheDir", "", "Cache Dir", "Directory for Hugo's file caches; defaults to an OS temp directory when unset.", .advanced),
    stringEntry("contentDir", "content", "Content Dir", "Directory containing site content.", .advanced),
    stringEntry("dataDir", "data", "Data Dir", "Directory of structured data files available via site.Data.", .advanced),
    stringEntry("i18nDir", "i18n", "i18n Dir", "Directory of translation files.", .advanced),
    stringEntry("layoutDir", "layouts", "Layout Dir", "Directory of templates.", .advanced),
    stringEntry("publishDir", "public", "Publish Dir", "Output directory the built site is written to.", .advanced),
    stringEntry("resourceDir", "resources", "Resource Dir", "Directory Hugo caches generated/processed resources in.", .advanced),
    entry("staticDir", .stringOrStringArray, .value("static"), "Static Dir", "Directory (or directories) copied as-is to the output, unprocessed.", .advanced),
    stringEntry("themesDir", "themes", "Themes Dir", "Directory containing installed themes.", .advanced)
]

// MARK: - §2.5 mechanism 1 — deprecated-but-schema'd entries (not co-located above)

private let deprecatedEntries: [ConfigSettingSpec] = [
    deprecatedArrayEntry("ignoreFiles", [], "Ignore Files (legacy)", "Regexes of files to exclude from processing.", .advanced, since: "unspecified", message: "Superseded by module mount excludeFiles patterns; not auto-migrated.", replacement: nil),
    // `author`/`social` deliberately absent: both were `.dictionary`, which has no working
    // control, so they rendered as "Deprecated" + "Coming in a later phase". They now fall
    // through to Unknown Keys, which gives them a real editor. See ConfigSchemaPlaceholderTests.
    deprecatedStringEntry("markup.goldmark.parser.autoHeadingIDType", "github", "Heading ID Style (legacy key)", "Legacy name for the heading-ID slug algorithm setting.", .advanced, since: "0.144.0", message: "Renamed to markup.goldmark.parser.autoIDType.", replacement: "markup.goldmark.parser.autoIDType"),
    deprecatedBoolEntry("markup.goldmark.renderHooks.image.enableDefault", true, "Image Render Hook (legacy key)", "Legacy name for opting into Hugo's embedded image render hook.", .advanced, since: "0.148.0", message: "Renamed to markup.goldmark.renderHooks.image.useEmbedded.", replacement: "markup.goldmark.renderHooks.image.useEmbedded"),
    deprecatedBoolEntry("markup.goldmark.renderHooks.link.enableDefault", true, "Link Render Hook (legacy key)", "Legacy name for opting into Hugo's embedded link render hook.", .advanced, since: "0.148.0", message: "Renamed to markup.goldmark.renderHooks.link.useEmbedded.", replacement: "markup.goldmark.renderHooks.link.useEmbedded")
]

/// `staticDir0`...`staticDir10`: pre-array-support indexed static directory
/// overrides. Generated rather than hand-written 11 times.
private let staticDirLegacyEntries: [ConfigSettingSpec] = (0...10).map { index in
    deprecatedStringEntry(
        "staticDir\(index)", nil, "Static Dir \(index) (legacy)",
        "Legacy indexed static directory override, from before staticDir accepted an array.",
        .advanced, since: "unspecified",
        message: "Use the staticDir array or module mounts instead.", replacement: "staticDir"
    )
}

// MARK: - §3.7(c) unknown-keys editor needs no schema entries (recursive editor over anything unmatched).

/// The static schema table (CONFIG-SCHEMA-SPEC §2.3, §3). Every row is data —
/// no logic lives here beyond the tiny builder functions above.
enum ConfigSchema {
    static let all: [ConfigSettingSpec] =
        essentialsEntries +
        contentBuildEntries +
        urlsTaxonomiesEntries +
        markupEntries +
        markupAdvancedEntries +
        integrationsEntries +
        advancedRootEntries +
        directoryOverrideEntries +
        deprecatedEntries +
        staticDirLegacyEntries +
        rawOnlySpecs

    // MARK: - Raw-only sections (§3.7)

    /// (key, label, help) for each section Hugo owns but Victor shows
    /// read-only ("Edit in Raw"). 19 entries per §3.7.
    static let rawOnlySections: [(key: String, label: String, help: String)] = [
        ("build", "Build Cache Options", "Low-level build/render cache tuning; edit via Raw."),
        ("caches", "Caches", "Cache backend configuration (dir/maxAge) per cache type; edit via Raw."),
        ("httpcache", "HTTP Cache", "Cache policy for remote resource fetches; edit via Raw."),
        ("cascade", "Cascade", "Front matter cascade rules applied via config; edit via Raw."),
        ("deployment", "Deployment", "hugo deploy target and matcher configuration; edit via Raw."),
        ("frontmatter", "Front Matter", "Date/lastmod/publishdate field-name resolution order; edit via Raw."),
        ("languages", "Languages", "Per-language site configuration; edit via Raw."),
        ("mediatypes", "Media Types", "Custom or overridden MIME type definitions; edit via Raw."),
        ("contenttypes", "Content Types", "File extensions treated as page content; edit via Raw."),
        ("module", "Modules", "Hugo Modules imports, mounts, and replacements; edit via Raw."),
        ("outputformats", "Output Formats", "Custom output format definitions; edit via Raw."),
        ("related.indices", "Related Indices", "Index definitions used by the related-content algorithm; edit via Raw."),
        ("roles", "Roles", "Site content role dimension definitions; edit via Raw."),
        ("security", "Security", "Allow-lists for exec, templates, and HTTP access; edit via Raw."),
        ("segments", "Segments", "Named build-segment definitions; edit via Raw."),
        ("server", "Server", "hugo server-only settings (redirects, headers); edit via Raw."),
        ("versions", "Versions", "Site content version dimension definitions; edit via Raw."),
        ("minify.tdewolff", "Minifier Tuning", "Per-format tdewolff minifier tuning options; edit via Raw."),
        ("imaging.exif", "EXIF Handling", "EXIF metadata extraction options for images; edit via Raw.")
    ]

    static let rawOnlySectionKeys: [String] = rawOnlySections.map(\.key)

    // MARK: - §4 Enum catalogs

    /// §4.1 titleCaseStyle (case-insensitive; unknown ⇒ AP).
    static let titleCaseStyles: [String] = ["ap", "chicago", "go", "firstupper", "none"]

    /// §4.2 autoIDType.
    static let autoIDTypes: [String] = ["github", "github-ascii", "blackfriday"]

    /// §4.3 Page kinds (disableKinds / outputs rows), lowercase for comparison.
    static let pageKinds: [String] = [
        "page", "home", "section", "taxonomy", "term",
        "rss", "sitemap", "sitemapindex", "robotstxt", "404"
    ]

    /// §4.4 Built-in output format names.
    static let outputFormatNames: [String] = [
        "html", "rss", "amp", "alias", "calendar", "css", "csv", "json",
        "markdown", "robots", "sitemap", "sitemapindex", "webappmanifest"
    ]

    /// §4.5 Chroma styles (chroma v2.27.0, transcribed verbatim from the
    /// spec's list). Default `monokai`.
    static let chromaStyles: [String] = [
        "abap", "algol", "algol_nu", "arduino", "ashen", "aura-theme-dark", "aura-theme-dark-soft",
        "autumn", "average", "base16-snazzy", "borland", "bw", "catppuccin-frappe", "catppuccin-latte",
        "catppuccin-macchiato", "catppuccin-mocha", "colorful", "darcula", "doom-one", "doom-one2",
        "dracula", "emacs", "evergarden", "friendly", "fruity", "github", "github-dark", "gruvbox",
        "gruvbox-light", "hr_high_contrast", "hrdark", "igor", "kanagawa-dragon", "kanagawa-lotus",
        "kanagawa-wave", "lovelace", "manni", "modus-operandi", "modus-vivendi", "monokai",
        "monokailight", "murphy", "native", "nord", "nordic", "onedark", "onesenterprise",
        "paraiso-dark", "paraiso-light", "pastie", "perldoc", "pygments", "rainbow_dash", "rose-pine",
        "rose-pine-dawn", "rose-pine-moon", "rpgle", "rrt", "solarized-dark", "solarized-dark256",
        "solarized-light", "swapoff", "tango", "tokyonight-day", "tokyonight-moon", "tokyonight-night",
        "tokyonight-storm", "trac", "vim", "vs", "vulcan", "witchhazel", "xcode", "xcode-dark"
    ]

    /// §4.6 sitemap.changeFreq ("" = omit changefreq entirely).
    static let sitemapChangeFreqs: [String] = ["", "always", "hourly", "daily", "weekly", "monthly", "yearly", "never"]

    /// §4.7 renderHooks useEmbedded.
    static let renderHooksUseEmbedded: [String] = ["always", "auto", "fallback", "never"]

    /// §4.9 page sort orders.
    static let pageSortOrders: [String] = ["asc", "desc"]

    /// IANA time zone identifiers backing the `timeZone` `.choice` picker
    /// (Phase 5 task brief item 7). Sorted for deterministic ordering —
    /// `TimeZone.knownTimeZoneIdentifiers`'s own order isn't guaranteed.
    static let timeZoneIdentifiers: [String] = TimeZone.knownTimeZoneIdentifiers.sorted()

    // MARK: - Lookup

    /// Key → spec, built once. Tabs re-plumbed onto `ConfigFieldView` (Phase 1d)
    /// look up their handful of fields by key rather than hardcoding entries a
    /// second time — the table stays the single source of truth.
    private static let byKey: [String: ConfigSettingSpec] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.key, $0) }
    )

    /// The spec for `key`, if one exists. `nil` is a programmer error at a
    /// tab call site (a typo'd key) — callers force-unwrap deliberately so
    /// the mistake surfaces immediately in debug/test runs rather than
    /// silently dropping a field from the UI.
    static func spec(for key: String) -> ConfigSettingSpec? {
        byKey[key]
    }
}

private let rawOnlySpecs: [ConfigSettingSpec] = ConfigSchema.rawOnlySections.map { rawOnlyEntry($0.key, $0.label, $0.help) }
