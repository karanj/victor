# Victor - macOS Hugo CMS

A native macOS app built with SwiftUI that provides a sophisticated editing experience for [Hugo](https://gohugo.io/) static sites.

![Screenshot of Victor in action](Docs/Victor-screenshot.png?raw=true "An example of Victor in use")

<p align="center" width="100%">
    <img src="https://github.com/karanj/victor/blob/main/Docs/icon_256x256.png?raw=true">
</p>

## Quick Summary

| | |
|---|---|
| **Status** | Production ready, clean build |
| **Codebase** | 91 Swift files, ~25,000 lines of code |
| **Tests** | 200+ tests |
| **Platform** | macOS 14.0 (Sonoma) or later |

## Why Victor?

[Victor Hugo](https://en.wikipedia.org/wiki/Victor_Hugo) was a renowned French author; I have immensely enjoyed his most famous works, _Les Miserables_ and _The Hunchback of Notre-Dame_. 
So when I went to come up a name for something to help me create more in Hugo, my first thought was actually [Hugo Weaving](https://en.wikipedia.org/wiki/Hugo_Weaving) but he's still alive and also not a writer.
And _then_ I remembered [Victor & Hugo](https://en.wikipedia.org/wiki/Victor_%26_Hugo:_Bunglers_in_Crime), a great screwball crime comedy animation I enjoyed immensely as a kid (I can still recall the theme song).

I built this for myself after migrating websites from WordPress but missing a proper CMS experience. I tried various Hugo CMSes but wanted a native Mac app for writing.

Victor is opinionated - I wanted to see raw markdown while having lightweight previews and shortcuts for Hugo's shortcodes. It's suited to writers who want control over their content without full WYSIWYG abstraction.

**Note**: I make no warranties that it won't break your site. Use git to undo any issues.

## Features at a Glance

- **Full Hugo site browsing** - content, config, static, assets, layouts, data, themes
- **Markdown editing** with live preview and formatting toolbar
- **Frontmatter editing** - YAML, TOML, JSON with form or raw editing
- **Hugo config GUI** - edit hugo.toml/yaml/json with a form interface
- **Asset browser** - grid/list view with drag-drop insertion
- **Hugo server integration** - live preview and build error display
- **Template editor** - Go template syntax highlighting
- **Data file editor** - GUI for data/ directory files
- **Archetype support** - create content from templates
- **Focus mode** - distraction-free writing
- **Auto-save** with conflict detection

For detailed usage instructions, see the **[User Manual](Docs/USER-MANUAL.md)**.

## Requirements

- macOS 14.0 (Sonoma) or later
- [Hugo](https://gohugo.io/installation/) installed on your system

## Installation

1. Download **Victor.zip** from the [latest release](https://github.com/karanj/victor/releases/latest)
2. Expand the zip and drag Victor to your Applications folder

## Building from Source

For developers who want to build from source:

```bash
# Clone and build
git clone https://github.com/karanj/victor.git
cd victor
xcodegen generate
open Victor.xcodeproj
# Press ⌘R to build and run
```

Requires Xcode 15+ and Swift 5.9+.

To build a distributable DMG:
```bash
./scripts/build-release.sh
```

## Architecture

- **Pattern**: MVVM with `@Observable` (SwiftUI)
- **State Management**: `@MainActor` for thread-safe UI updates
- **File I/O**: Async/await with security-scoped bookmarks
- **Background work**: Actor-based services (AutoSaveService, HugoServerService)

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [Down](https://github.com/johnxnguyen/Down) | 0.11.0 | Markdown to HTML |
| [Yams](https://github.com/jpsim/Yams) | 5.x | YAML parsing |
| [TOMLKit](https://github.com/LebJe/TOMLKit) | 0.6.0 | TOML parsing |

## Testing

```bash
# Run all tests
xcodebuild test -project Victor.xcodeproj -scheme Victor -destination 'platform=macOS'

# Run specific test suite
xcodebuild test -project Victor.xcodeproj -scheme Victor -only-testing:VictorTests/HugoConfigParserTests
```

| Test Suite | Tests | Coverage |
|------------|-------|----------|
| HugoConfigParserTests | 61 | Config parsing (TOML, YAML, JSON) |
| FrontmatterParserTests | 60 | Frontmatter parsing |
| DataFileParserTests | 22 | Data file parsing |
| ArchetypeManagerTests | 23 | Archetype processing |
| HugoServerTests | 19 | Hugo server management |
| EditorViewModelTests | 12 | Editor race conditions |

## Project Structure

```
Victor/
├── Models/           # HugoSite, ContentFile, Frontmatter, FileNode, FileType
├── ViewModels/       # SiteViewModel, EditorViewModel, TextEditorViewModel
├── Services/         # FileSystemService, AutoSaveService, HugoServerService, Parsers
├── Views/            # SwiftUI views organized by feature
└── VictorTests/      # Test suites
```

## Documentation

- **[User Manual](Docs/USER-MANUAL.md)** - How to use Victor
- **[Hugo Server Integration](Docs/HUGO-SERVER-INTEGRATION.md)** - Live preview setup
- **[Data & Archetypes Guide](Docs/DATA-ARCHETYPES-GUIDE.md)** - Working with data files

## Contributing

Contributions welcome for:

- Bug fixes and real-world testing
- UI/UX enhancements
- Accessibility improvements (VoiceOver, keyboard navigation)
- Test coverage expansion
- Documentation improvements

## Future Plans

Planned features are tracked in the project's issue tracker. Key areas:

- File system watching (FSEvents) for auto-reload
- Git integration (status, commit, push)
- Syntax highlighting for code blocks in preview
- Multi-file tabs
- Custom themes/color schemes

## License

MIT License - see [LICENSE](LICENSE) for details.

## Credits

Built with SwiftUI, [Down](https://github.com/johnxnguyen/Down), [Yams](https://github.com/jpsim/Yams), [TOMLKit](https://github.com/LebJe/TOMLKit), and [Claude Code](https://claude.ai/code).

Thanks to the [Hugo](https://gohugo.io/) team for their excellent static site generator.

---

**Victor** - A modern Hugo CMS for macOS
