# Data & Archetypes Management Guide

This document describes the data file editing, archetype management, and translation editing features added in Phase 5.

## Overview

Victor now supports editing Hugo's data files, creating content from archetypes, and managing i18n translation files—all with native macOS UI.

## Data Files (data/ directory)

Hugo's `data/` directory contains structured data files (YAML, JSON, TOML) that can be accessed in templates via `.Site.Data`.

### Viewing & Editing Data Files

1. Navigate to a file in the `data/` directory in the sidebar
2. Click to open it in the **Data File Editor**

The editor provides two modes:

- **Form View**: Visual editor with dynamic fields
  - Dictionary data: Key-value pairs with add/remove
  - Array data: List items with reorder (↑↓) and delete
  - Nested structures: Expandable sections
  - Type-aware editing: Text fields, checkboxes, number inputs

- **Raw View**: Direct text editing with syntax highlighting
  - Format preserved (YAML/JSON/TOML)
  - Changes sync between Form and Raw views

### Creating New Data Files

1. Right-click on the `data/` folder (or any subfolder)
2. Select **"New Data File..."**
3. Enter a filename and select format (YAML, JSON, or TOML)
4. Click **Create**

The new file opens automatically in the editor.

## Archetypes (archetypes/ directory)

Archetypes are content templates that define the initial frontmatter and body for new content files.

### How Archetypes Work

When you create content from an archetype:

1. Victor loads archetypes from `archetypes/`
2. Template variables are replaced:
   - `{{ .Title }}` → Your content title
   - `{{ .Date }}` → Current ISO 8601 timestamp
3. The processed content is saved to the target location

### Creating Content from Archetypes

1. Right-click on any folder in `content/`
2. Select **"New Content from Archetype..."**
3. Choose an archetype template (or use Default)
4. Enter a title for your content
5. Optionally specify a custom filename
6. Click **Create**

### Archetype File Format

Archetypes are markdown files with frontmatter:

```markdown
---
title: "{{ .Title }}"
date: {{ .Date }}
draft: true
categories: []
tags: []
---

Write your content here...
```

Supported frontmatter formats:
- YAML (`---` delimiters)
- TOML (`+++` delimiters)
- JSON (opening `{`)

### Default Archetype

If no archetypes exist, Victor uses a default template:

```markdown
---
title: "Your Title"
date: 2025-01-10T12:00:00-05:00
draft: true
---

```

## Translation Files (i18n/ directory)

Hugo uses the `i18n/` directory for multilingual string translations.

### Viewing & Editing Translations

1. Navigate to a file in the `i18n/` directory (e.g., `en.yaml`, `fr.toml`)
2. Click to open it in the **Translation Editor**

Features:
- **Key-value list**: All translation strings in a searchable table
- **Search**: Filter translations by key or value
- **Plural support**: Expand entries to edit plural forms (other, one, few, many, zero)
- **Form/Raw toggle**: Switch between visual and text editing
- **Language badge**: Shows the language code (EN, FR, DE, etc.)

### Creating New Translation Files

1. Right-click on the `i18n/` folder
2. Select **"New Translation File..."**
3. Select a language from the quick-pick grid or enter a custom code
4. Choose format (YAML, JSON, or TOML)
5. Click **Create**

Common language codes available:
- EN (English), ES (Spanish), FR (French)
- DE (German), IT (Italian), PT (Portuguese)
- ZH (Chinese), JA (Japanese), KO (Korean)
- AR (Arabic), RU (Russian), NL (Dutch)

### Translation File Format

Simple translations:
```yaml
hello: "Hello"
welcome: "Welcome to our site"
```

With plural forms:
```yaml
items:
  one: "{{ .Count }} item"
  other: "{{ .Count }} items"
```

## File Structure

Files added in Phase 5:

```
Victor/
├── Models/
│   ├── DataFile.swift          # Data file model
│   └── Archetype.swift         # Archetype template model
├── Services/
│   ├── DataFileParser.swift    # Parse/serialize data files
│   └── ArchetypeManager.swift  # Load and process archetypes
└── Views/
    ├── DataEditor/
    │   ├── DataFileEditorView.swift   # Main data editor
    │   └── NewDataFileView.swift      # Create new data file dialog
    ├── NewContent/
    │   └── NewContentView.swift       # Create from archetype dialog
    └── TranslationEditor/
        ├── TranslationEditorView.swift  # Main translation editor
        └── NewTranslationFileView.swift # Create new translation dialog
```

## Context Menu Reference

| Folder Type | Menu Item | Description |
|-------------|-----------|-------------|
| `content/` | New Content from Archetype... | Create content using a template |
| `content/` | New Markdown File | Create empty markdown file |
| `data/` | New Data File... | Create YAML/JSON/TOML data file |
| `i18n/` | New Translation File... | Create translation file for a language |
| Any folder | New Folder | Create subfolder |
| Any folder | Reveal in Finder | Show in macOS Finder |
| Any folder | Copy Path | Copy folder path to clipboard |

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘S | Save current file |
| ⌘1 | Switch to Form view |
| ⌘2 | Switch to Raw view |

## Tips

1. **Data file arrays**: Click the disclosure triangle to expand array items for editing
2. **Translation search**: Use the search field to quickly find specific translation keys
3. **Archetype naming**: Name archetypes after content types (e.g., `post.md`, `page.md`) for clarity
4. **Format consistency**: Keep all data files in the same format for easier maintenance
