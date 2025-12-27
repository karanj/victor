# Victor UI/UX Improvement Plan

**Created**: 2025-12-27
**Status**: Proposal for Review
**Scope**: Native macOS UI/UX enhancements for Hugo CMS

---

## Executive Summary

This plan proposes UI/UX improvements to make Victor feel more polished and native on macOS. The improvements focus on:
1. **Collapsible Preview Panel** - Toggle or resize the preview
2. **Enhanced Editor Experience** - Line numbers, better toolbar, focus mode
3. **Improved Navigation** - Tabs, breadcrumbs, file status indicators
4. **Native macOS Patterns** - Inspector panels, unified toolbar, keyboard-first design
5. **Polish & Refinement** - Animations, typography, visual hierarchy

---

## 1. Collapsible Preview Panel

### Current State
The preview panel is always visible, taking 50% of the available space. Users cannot hide it when focusing on writing.

### Proposed Solutions

#### Option A: Toggle Button (Recommended)
Add a toolbar button to show/hide the preview panel entirely.

```
┌─────────────────────────────────────────────────────────────────────┐
│ [≡] Victor    │   [B] [I] [H] ...   [👁 Preview]   [💾 Save]        │
├───────────────┼─────────────────────────────────────────────────────┤
│ 📁 content/   │                                                     │
│  ├─ posts/    │   # My Blog Post                                    │
│  │  ├─ hello  │                                                     │
│  │  └─ world  │   This is some markdown content...                  │
│  └─ about.md  │                                                     │
│               │                                                     │
│               │   Preview hidden - full width editor                │
│               │                                                     │
└───────────────┴─────────────────────────────────────────────────────┘
         ↑ Click [👁 Preview] to toggle
```

**Implementation**:
- Add `isPreviewVisible: Bool` to `SiteViewModel` (persisted)
- When hidden, editor takes full width
- Keyboard shortcut: `⌘⇧P` to toggle
- Animate collapse/expand with `withAnimation(.easeInOut(duration: 0.2))`

#### Option B: Resizable Split View
Replace fixed split with draggable divider, allowing any ratio.

```
┌─────────────────────────────────────────────────────────────────────┐
│                              Editor                    │   Preview  │
│                                                       ◀│▶           │
│   # My Blog Post                                       │   Rendered │
│                                                        │   HTML     │
│   This is markdown...                                  │            │
│                                                       ◀│▶  (drag)   │
└────────────────────────────────────────────────────────┴────────────┘
```

**Implementation**:
- Use `HSplitView` (AppKit) or custom drag gesture
- Persist ratio in UserDefaults
- Double-click divider to reset to 50/50
- Minimum width constraints (200pt each side)

#### Option C: Tab-Based Layout
Editor and Preview as tabs, with optional split view.

```
┌─────────────────────────────────────────────────────────────────────┐
│ [≡]   │  [ Editor ]  [ Preview ]  [ Split ▾ ]                       │
├───────┼─────────────────────────────────────────────────────────────┤
│       │                                                             │
│ Files │              Currently active tab content                   │
│       │                                                             │
└───────┴─────────────────────────────────────────────────────────────┘
```

**Recommendation**: Start with **Option A** (toggle) as it's simplest. Consider adding **Option B** (resize) later for power users.

---

## 2. Enhanced Editor Experience

### 2.1 Line Numbers

Add optional line numbers in the gutter, matching Xcode/VS Code style.

```
┌──────────────────────────────────────────────────────────────────┐
│  1 │ ---                                                          │
│  2 │ title: "My Blog Post"                                        │
│  3 │ date: 2025-01-15                                             │
│  4 │ draft: false                                                 │
│  5 │ ---                                                          │
│  6 │                                                              │
│  7 │ # Introduction                                               │
│  8 │                                                              │
│  9 │ This is the first paragraph of my post.                      │
│ 10 │                                                              │
└──────────────────────────────────────────────────────────────────┘
```

**Implementation**:
- Create `LineNumberRulerView` as NSRulerView subclass
- Attach to NSScrollView's vertical ruler
- Sync line number highlighting with cursor position
- Use secondary text color for numbers
- Toggle via View menu: `View → Show Line Numbers`
- Persist preference in UserDefaults

### 2.2 Current Line Highlighting

Subtle highlight on the current line for better focus.

```
┌──────────────────────────────────────────────────────────────────┐
│  7 │ # Introduction                                               │
│  8 │                                                              │
│  9 │ This is the first paragraph of my post.      ← cursor here   │
│    │ ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒  (subtle highlight)  │
│ 10 │                                                              │
└──────────────────────────────────────────────────────────────────┘
```

**Implementation**:
- Override `drawBackground(in:)` in NSTextView
- Draw subtle fill behind current line (10% opacity of accent color)
- Update on selection change via delegate

### 2.3 Improved Toolbar Design

Redesign the editor toolbar for better visual hierarchy and grouping.

**Current**:
```
[B] [I] [H] [•] [1.] [</>] [🔗] [🖼] [❝]     [👁] [💾 Save]
```

**Proposed** (grouped with separators):
```
┌──────────────────────────────────────────────────────────────────┐
│ [B] [I] [U] │ [H1▾] │ [•] [1.] │ [</>] [❝] │ [🔗] [🖼]  ║  [👁 Preview] [💾] │
│   Text      │ Heads │  Lists   │   Code    │  Insert   ║     Actions        │
└──────────────────────────────────────────────────────────────────┘
```

**Improvements**:
1. **Logical grouping** with vertical separators
2. **Heading dropdown** for H1-H6 selection
3. **Underline** option (some markdown flavors support it)
4. **Consistent iconography** using SF Symbols
5. **Tooltips** showing keyboard shortcuts
6. **Visual separator** between content tools and actions

### 2.4 Focus/Zen Mode

Distraction-free writing mode that hides UI chrome.

```
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│                                                                  │
│                                                                  │
│                   # My Blog Post                                 │
│                                                                  │
│                   This is the first paragraph.                   │
│                   Just the content, nothing else.                │
│                                                                  │
│                                                                  │
│                                                                  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
           Full screen, centered text, no toolbar/sidebar
```

**Implementation**:
- Enter via `View → Focus Mode` or `⌃⌘F`
- Hide sidebar, toolbar, preview, frontmatter panel
- Center text with comfortable max-width (700pt)
- Dim background slightly
- Show UI on mouse movement (auto-hide after 2s)
- Press Esc to exit
- Typewriter mode option: keep current line vertically centered

### 2.5 Word/Character Count

Show document statistics in a subtle footer or status bar.

```
┌──────────────────────────────────────────────────────────────────┐
│                          Editor Content                          │
│                              ...                                 │
├──────────────────────────────────────────────────────────────────┤
│  📄 1,234 words  •  6,789 characters  •  Line 42, Col 15         │
└──────────────────────────────────────────────────────────────────┘
```

**Implementation**:
- Calculate on text change (debounced)
- Show in footer bar below editor
- Optional: estimated reading time (words ÷ 200)
- Click to see detailed stats (paragraphs, sentences, etc.)

---

## 3. Improved Navigation

### 3.1 File Tabs (Multi-File Editing)

Open multiple files in tabs, like Xcode or VS Code.

```
┌──────────────────────────────────────────────────────────────────┐
│ [≡]   │ [hello.md ●] [about.md] [config.toml] [+]                │
├───────┼──────────────────────────────────────────────────────────┤
│       │                                                          │
│ Files │             Content of hello.md                          │
│       │                     ● = unsaved changes                  │
└───────┴──────────────────────────────────────────────────────────┘
```

**Features**:
- Unsaved indicator (dot) on tab
- Middle-click or X to close tab
- Drag tabs to reorder
- `⌘W` closes current tab
- `⌘⇧[` / `⌘⇧]` to switch tabs
- Restore open tabs on app launch

**Implementation**:
- Add `openFiles: [ContentFile]` to SiteViewModel
- Create `TabBarView` above editor
- Each tab maintains its own EditorViewModel
- Consider max tab limit with overflow menu

### 3.2 Breadcrumb Navigation

Show file path as clickable breadcrumbs for quick navigation.

```
┌──────────────────────────────────────────────────────────────────┐
│ 📁 content  ›  posts  ›  2025  ›  hello.md                       │
├──────────────────────────────────────────────────────────────────┤
│                         Editor Content                           │
└──────────────────────────────────────────────────────────────────┘
```

**Features**:
- Click any segment to navigate to that folder
- Shows current location context
- Dropdown on click shows siblings

### 3.3 File Status Indicators

Show file state in sidebar with visual indicators.

```
📁 content/
 ├─ posts/
 │  ├─ hello.md      ● (modified, unsaved)
 │  ├─ world.md      ✓ (saved)
 │  └─ draft.md      ⚠️ (conflict detected)
 └─ about.md         ☆ (recently opened)
```

**Colors**:
- Orange dot: unsaved changes
- Green checkmark: recently saved
- Yellow warning: external modification
- Blue star: recently accessed

### 3.4 Quick Open (⌘P)

Fuzzy file finder like VS Code's quick open.

```
┌──────────────────────────────────────────────────────────────────┐
│  🔍 hello                                                    [×] │
├──────────────────────────────────────────────────────────────────┤
│  📄 content/posts/hello.md                          (most recent)│
│  📄 content/projects/hello-world/index.md                        │
│  📄 content/drafts/hello-again.md                                │
└──────────────────────────────────────────────────────────────────┘
```

**Implementation**:
- Overlay modal on `⌘P`
- Fuzzy matching on file names and paths
- Recent files shown by default
- Arrow keys to navigate, Enter to open
- Real-time filtering as you type

---

## 4. Native macOS Patterns

### 4.1 Inspector Panel (Right Sidebar)

Move frontmatter editing to a right-side inspector, like Xcode/Pages/Keynote.

```
┌────────┬──────────────────────────────────────┬────────────────────┐
│        │                                      │   📋 Inspector     │
│ Files  │           Editor                     ├────────────────────┤
│        │                                      │ Title:             │
│        │   # My Blog Post                     │ [My Blog Post    ] │
│        │                                      │                    │
│        │   Content here...                    │ Date:              │
│        │                                      │ [2025-01-15      ] │
│        │                                      │                    │
│        │                                      │ Draft: [ ] Yes     │
│        │                                      │                    │
│        │                                      │ Tags:              │
│        │                                      │ [hugo] [cms] [+]   │
└────────┴──────────────────────────────────────┴────────────────────┘
```

**Advantages**:
- Standard macOS pattern (Xcode, Finder, Pages)
- Frontmatter always visible while editing
- Doesn't reduce vertical editor space
- Toggle with `⌥⌘I` (standard inspector shortcut)

**Implementation**:
- Optional: keep bottom panel as alternative
- Add `inspectorPosition: .right | .bottom` preference
- Inspector can have multiple tabs: Metadata, Statistics, History

### 4.2 Unified Toolbar

Use macOS 11+ unified toolbar style with title/subtitle.

```
┌──────────────────────────────────────────────────────────────────┐
│ [<] [>]  │  My Hugo Site           │  [🔍] [📋] [👁] [💾] [⚙️]  │
│          │  content/posts/hello.md │                             │
├──────────┴───────────────────────────────────────────────────────┤
```

**Features**:
- Centered title (site name) with subtitle (current file path)
- Toolbar buttons aligned right
- Back/forward navigation if implementing file history
- Search field in toolbar (optional)

### 4.3 Touch Bar Support

For MacBooks with Touch Bar (legacy but still used).

```
┌─────────────────────────────────────────────────────────────────────┐
│  [B] [I] [H▾]  │  [•] [1.]  │  [</>] [❝]  │  [🔗] [🖼]  │  [💾 Save] │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.4 Menu Bar Refinement

Organize menus following Apple HIG standards.

```
Victor  File  Edit  View  Format  Navigate  Window  Help
        ├─ New Post...        ⌘N
        ├─ Open Site...       ⌘O
        ├─ Open Recent       ▶
        ├─ ─────────────────────
        ├─ Save               ⌘S
        ├─ Save As...         ⌘⇧S
        ├─ Export HTML...
        ├─ ─────────────────────
        └─ Close              ⌘W
```

**New Menu Items**:
- `Format` menu: Bold, Italic, Heading submenu, Lists
- `Navigate` menu: Go to Line (⌘G), Quick Open (⌘P), Next/Prev File
- `View` menu: Show/Hide Preview, Inspector, Line Numbers, Focus Mode

---

## 5. Polish & Refinement

### 5.1 Animations & Transitions

Add subtle animations for a polished feel.

| Action | Animation |
|--------|-----------|
| Open file | Fade in editor content (0.15s) |
| Toggle preview | Slide in/out with resize (0.2s) |
| Expand folder | Smooth disclosure (0.15s) - already exists |
| Show frontmatter | Slide up from bottom (0.2s) - already exists |
| Save indicator | Checkmark pulse animation |
| Error/warning | Subtle shake or flash |

### 5.2 Typography Refinement

Improve font choices and sizing for readability.

**Editor**:
- Current: 13pt system monospace
- Proposed: User-configurable (12-18pt range)
- Consider: JetBrains Mono, SF Mono, or Menlo
- Line height: 1.5 for better readability

**Sidebar**:
- File names: 13pt system font (body)
- Metadata/badges: 11pt system font (caption)
- Folder headers: 12pt medium weight

**Preferences Panel** (new):
```
┌─────────────────────────────────────────────────────────────────────┐
│                         Appearance                                  │
│  ─────────────────────────────────────────────────────────────────  │
│                                                                     │
│  Editor Font:    [SF Mono        ▾]    Size: [14 ▾]                │
│                                                                     │
│  Line Spacing:   ○ Compact  ● Normal  ○ Relaxed                    │
│                                                                     │
│  Theme:          ○ System  ○ Light  ○ Dark                         │
│                                                                     │
│  □ Show line numbers                                                │
│  □ Highlight current line                                           │
│  □ Show invisible characters                                        │
└─────────────────────────────────────────────────────────────────────┘
```

### 5.3 Empty States

Design helpful empty states for better onboarding.

**No Site Open**:
```
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│                         📁                                       │
│                                                                  │
│                   Open a Hugo Site                               │
│                                                                  │
│              Drag a folder here or click to browse               │
│                                                                  │
│                  [ Open Folder... ]                              │
│                                                                  │
│              Recent:                                             │
│              • ~/Sites/my-blog                                   │
│              • ~/Sites/portfolio                                 │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

**No File Selected**:
```
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│                         📝                                       │
│                                                                  │
│                   Select a file to edit                          │
│                                                                  │
│              Choose a markdown file from the sidebar             │
│              or press ⌘N to create a new post                    │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 5.4 Keyboard-First Design

Ensure all actions are accessible via keyboard.

**New Shortcuts**:
| Shortcut | Action |
|----------|--------|
| `⌘P` | Quick Open (fuzzy file finder) |
| `⌘⇧P` | Toggle Preview |
| `⌥⌘I` | Toggle Inspector |
| `⌃⌘F` | Focus Mode |
| `⌘G` | Go to Line |
| `⌘⇧[` | Previous Tab |
| `⌘⇧]` | Next Tab |
| `⌘1-9` | Switch to Tab N |
| `⌘\` | Toggle Sidebar |
| `⌃Tab` | Cycle through panes |

### 5.5 Contextual Menus

Rich right-click menus throughout the app.

**Editor Context Menu**:
```
┌─────────────────────────────┐
│ Cut                    ⌘X   │
│ Copy                   ⌘C   │
│ Paste                  ⌘V   │
├─────────────────────────────┤
│ Bold                   ⌘B   │
│ Italic                 ⌘I   │
│ Heading               ▶     │
├─────────────────────────────┤
│ Insert Link           ⌘K   │
│ Insert Image          ⌘⇧I  │
├─────────────────────────────┤
│ Look Up "word"              │
│ Search with Google          │
└─────────────────────────────┘
```

**Sidebar File Context Menu**:
```
┌─────────────────────────────┐
│ Open                        │
│ Open in New Tab             │
├─────────────────────────────┤
│ New File Here...            │
│ New Folder...               │
├─────────────────────────────┤
│ Rename...               ⏎   │
│ Duplicate                   │
│ Move to Trash          ⌘⌫   │
├─────────────────────────────┤
│ Reveal in Finder            │
│ Copy Path                   │
└─────────────────────────────┘
```

---

## 6. Implementation Priority

### Phase 1: Quick Wins (1-2 days each)

| Feature | Effort | Impact | Priority |
|---------|--------|--------|----------|
| Preview toggle button | Low | High | ⭐⭐⭐ |
| Word/character count | Low | Medium | ⭐⭐ |
| Line numbers (optional) | Medium | Medium | ⭐⭐ |
| Current line highlighting | Low | Medium | ⭐⭐ |
| Improved empty states | Low | Medium | ⭐⭐ |
| Additional keyboard shortcuts | Low | High | ⭐⭐⭐ |

### Phase 2: Enhanced Editor

| Feature | Effort | Impact | Priority |
|---------|--------|--------|----------|
| Toolbar redesign with grouping | Medium | Medium | ⭐⭐ |
| Quick Open (⌘P) | Medium | High | ⭐⭐⭐ |
| Focus/Zen mode | Medium | Medium | ⭐⭐ |
| Preferences panel | Medium | Medium | ⭐⭐ |
| Resizable preview split | Medium | Medium | ⭐⭐ |

### Phase 3: Multi-File & Navigation

| Feature | Effort | Impact | Priority |
|---------|--------|--------|----------|
| File tabs | High | High | ⭐⭐⭐ |
| Breadcrumb navigation | Medium | Medium | ⭐⭐ |
| File status indicators | Low | Medium | ⭐⭐ |
| Inspector panel (right sidebar) | High | Medium | ⭐⭐ |

### Phase 4: Advanced Polish

| Feature | Effort | Impact | Priority |
|---------|--------|--------|----------|
| Menu bar refinement | Medium | Medium | ⭐⭐ |
| Rich context menus | Medium | Medium | ⭐⭐ |
| Animation refinement | Low | Medium | ⭐ |
| Typography preferences | Medium | Low | ⭐ |

---

## 7. Mockup: Complete Redesigned UI

### Default View (with all enhancements)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ [◀][▶] │    My Hugo Site    │  [🔍] [📋 Inspector] [👁 Preview] [💾] [⚙️]    │
│        │  posts/hello.md    │                                                │
├────────┼────────────────────┴────────────────────────────────────────────────┤
│        │ [hello.md ●] [about.md] [config.toml]                          [+]  │
├────────┼─────────────────────────────────────────────────────────────────────┤
│        │ 📁 content › posts › hello.md                                       │
│        ├─────────────────────────────────────────────────────────────────────┤
│ 🔍 ────│ [B] [I] │ [H▾] │ [•] [1.] │ [</>] [❝] │ [🔗] [🖼]                    │
│        ├─────────────────────────────────────────────────────────────────────┤
│ 📁 cnt │   1 │ ---                              │                            │
│  posts │   2 │ title: "Hello World"             │  # Hello World             │
│   hello│   3 │ date: 2025-01-15                 │                            │
│  ● wrld│   4 │ draft: false                     │  Welcome to my blog!       │
│   draft│   5 │ ---                              │                            │
│  about │   6 │                                  │  This is the first         │
│        │   7 │ # Hello World                    │  paragraph of my post.     │
│        │   8 │                                  │                            │
│        │   9 │ Welcome to my blog!              │  ## Getting Started        │
│        │  10 │                                  │                            │
│        │  11 │ This is the first paragraph...   │  Here's how to begin...    │
│        │  12 │                                  │                            │
│        ├─────────────────────────────────────────────────────────────────────┤
│        │ 📄 234 words • 1,456 chars • Line 7, Col 12       Reading: 1 min    │
└────────┴─────────────────────────────────────────────────────────────────────┘
```

### Focus Mode

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│                                                                              │
│                                                                              │
│                           # Hello World                                      │
│                                                                              │
│                           Welcome to my blog! This is the first              │
│                           paragraph of my post about getting                 │
│                           started with Hugo.                                 │
│                                                                              │
│                           ## Getting Started                                 │
│                                                                              │
│                           Here's how to begin your journey...                │
│                                                                       ____   │
│                                                                      │ 7% │  │
│                                                                      └────┘  │
│                                                                  (progress)  │
└──────────────────────────────────────────────────────────────────────────────┘
         Press Esc to exit • Move mouse to show controls
```

### With Inspector Panel (alternative to bottom frontmatter)

```
┌────────┬───────────────────────────────────────────────┬─────────────────────┐
│        │ [hello.md ●] [about.md]                  [+]  │   📋 Metadata       │
├────────┼───────────────────────────────────────────────┤─────────────────────┤
│        │   1 │ # Hello World                          │ Title               │
│ 🔍 ────│   2 │                                        │ [Hello World      ] │
│        │   3 │ Welcome to my blog!                    │                     │
│ 📁 cnt │   4 │                                        │ Date                │
│  posts │   5 │ This is the first paragraph of my      │ [2025-01-15    📅] │
│   hello│   6 │ post about getting started with Hugo.  │                     │
│  ● wrld│   7 │                                        │ Draft               │
│        │   8 │ ## Getting Started                     │ [ ] Mark as draft   │
│        │   9 │                                        │                     │
│        │  10 │ Here's how to begin your journey...    │ Tags                │
│        │  11 │                                        │ [hugo] [blog] [+]   │
│        │  12 │ ```bash                                │                     │
│        │  13 │ hugo new site my-blog                  │ Categories          │
│        │  14 │ ```                                    │ [tutorials] [+]     │
│        │  15 │                                        │                     │
│        │  16 │ This will create a new Hugo site...    │ ─────────────────── │
│        │     │                                        │ 📊 Statistics       │
│        ├─────┴────────────────────────────────────────┤ 234 words           │
│        │ 📄 234 words • 1,456 chars • Ln 7, Col 12    │ 1,456 characters    │
└────────┴──────────────────────────────────────────────┴─────────────────────┘
```

---

## 8. Technical Considerations

### Performance
- Line numbers: Use `NSRulerView` for efficient rendering
- File tabs: Lazy load editor content per tab
- Quick Open: Pre-index file list on site load
- Animations: Keep under 0.3s, use SwiftUI's built-in

### Accessibility
- All new UI elements need VoiceOver labels
- Keyboard navigation for all new features
- Respect "Reduce Motion" system preference
- Maintain high contrast ratios

### State Persistence
New state to persist in UserDefaults:
- `isPreviewVisible`: Bool
- `previewSplitRatio`: Double
- `isInspectorVisible`: Bool
- `inspectorPosition`: String (.right | .bottom)
- `showLineNumbers`: Bool
- `highlightCurrentLine`: Bool
- `editorFontSize`: Int
- `editorFontName`: String
- `openTabs`: [String] (file paths)

### Migration
- All new preferences should have sensible defaults
- Existing users should see minimal visual change initially
- Progressive disclosure: power features discoverable but not intrusive

---

## 9. Questions for Review

Before implementation, please clarify:

1. **Preview Collapsibility**: Prefer toggle button or resizable split?
2. **Frontmatter Position**: Keep bottom panel, add inspector option, or replace entirely?
3. **File Tabs**: Essential or nice-to-have?
4. **Focus Mode**: Priority level?
5. **Preferences Panel**: How extensive should customization be?
6. **Quick Open (⌘P)**: High priority or defer?

---

## Appendix A: Reference Apps

### Design Inspiration
- **Xcode**: Inspector panel, unified toolbar, tabs
- **Nova (Panic)**: Beautiful native macOS editor
- **iA Writer**: Focus mode, typography
- **Bear**: Sidebar design, tags
- **Ulysses**: Three-column layout, markdown
- **VS Code**: Quick open, tabs, status bar

### Native macOS Patterns to Follow
- NavigationSplitView (three-column)
- Inspector panel (right sidebar)
- Unified toolbar with title
- Settings/Preferences window
- Document tabs
- Quick Open overlay
- Context menus everywhere

---

**End of UI/UX Improvement Plan**
