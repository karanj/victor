# Victor Models

Design rationale for `Victor/Models/`. Root-level contracts (per-keystroke invalidation, content dual storage) live in the repo-root `CLAUDE.md`.

## Model Type Strategy (Struct vs Class)

Models use `@Observable class` pattern by design. Evaluation of struct alternatives:

| Model | Pattern | Rationale |
|-------|---------|-----------|
| `Frontmatter` | class | 30+ mutable fields, `@Bindable` in 7+ views, version tracking for change detection |
| `FileNode` | class | Tree structure with `weak var parent`, recursive child relationships require reference semantics |
| `HugoConfig` | class | Form-bound editing via `@Bindable`, implements `EditableFile: AnyObject` protocol |
| `DataFile` | class | Form-bound editing, `EditableFile` protocol, change tracking via `originalContent` comparison |
| `ContentFile` | class | Contains `Frontmatter` reference, assigned to `FileNode.contentFile` for shared access |

**Why classes are appropriate here:**
1. **SwiftUI Binding**: `@Bindable` requires `@Observable` which works with classes. Form editors use two-way binding extensively.
2. **Shared Mutation**: Models are mutated from multiple locations (form fields, raw editor sync, auto-save). Reference semantics ensure all observers see the same state.
3. **Protocol Constraints**: `EditableFile` requires `AnyObject` for type-erased storage in dictionaries and generic handling.
4. **Tree Structures**: `FileNode` needs parent-child references that would cause copy-on-write issues with structs.

**Struct alternatives considered:**
- `FrontmatterSnapshot` already exists as an immutable struct for change detection - this is the appropriate pattern for value-type needs.
- `HugoMenuItem` is a struct because it's a simple data container without binding requirements.
