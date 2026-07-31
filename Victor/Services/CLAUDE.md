# Victor Services

Concurrency and serialization notes for `Victor/Services/`. Root-level contracts (per-keystroke invalidation, file-switching races, content dual storage) live in the repo-root `CLAUDE.md`.

## Serialization Gotchas

### Yams Type Normalization
Yams returns `Dictionary<AnyHashable, Any>` which can't serialize back. Must normalize:
```swift
private func normalizeForSerialization(_ value: Any) -> Any {
    if let dict = value as? [AnyHashable: Any] {
        var normalized: [String: Any] = [:]
        for (key, val) in dict {
            if let stringKey = key as? String {
                normalized[stringKey] = normalizeForSerialization(val)
            }
        }
        return normalized
    }
    // ... handle arrays
}
```

### Boolean Serialization
Always include boolean fields (don't skip `false`):
```swift
dictionary["buildDrafts"] = config.buildDrafts  // Always include
```

### YAML Width
Use `width: -1` to prevent line wrapping in Yams serialization.

## Service Concurrency Strategy
Services use different patterns based on their state and access patterns:

| Service | Pattern | Rationale |
|---------|---------|-----------|
| `HugoServerService` | `actor` | Manages process lifecycle, output buffering - mutable state with concurrent access |
| `AutoSaveService` | `actor` | Debounce timers, pending save tracking - mutable state modified from multiple call sites |
| `FileSystemService` | `class` + `@MainActor` methods | Stateless operations, but some methods update UI-bound data |
| Parsers (Frontmatter, Config, Data) | `class` with static `shared` | Stateless, thread-safe parsing operations |
| `AssetService` | `class` with static `shared` | Mostly reads with cached thumbnails - cache is thread-safe via actor isolation |

**When to use `actor`**: Service has mutable state accessed from multiple concurrent contexts (timers, callbacks, async operations).

**When `@MainActor` methods suffice**: Service is stateless but needs to update `@Observable` models or UI state.

**Dependency injection (victor-zw4, done):** `FileSystemService`, `AutoSaveService`, and `HugoServerService` — the three services tests actually need isolated instances of — are injectable via initializer parameters defaulting to `.shared` (e.g. `init(fileSystemService: FileSystemService = .shared)`), stored as `let`. Each has a non-private `init()` (all three are side-effect-free to construct) so tests can pass a fresh instance instead of the process-wide singleton — critical for `AutoSaveService`/`HugoServerService` since they're actors with mutable state that would otherwise leak between tests. `SiteViewModel` holds `fileSystemService`/`hugoServerService` as non-private `let`s (not `private`) so views that already hold a `siteViewModel` reference (`ServerControlView`, `LivePreviewPanel`, `EditorTextView`'s Coordinator) thread the same instance through instead of reaching `.shared` directly; `EditorViewModel`/`TextEditorViewModel` take their own injected service directly. Views with no such seam (`ServerLogView` — separate `Window` scene, no `SiteViewModel`; `PreferencesView` — zero-arg `Settings` scene) keep `.shared`, since threading an instance through would require adding SwiftUI Environment plumbing solely for that one call site — a cost the design explicitly avoids. No protocol abstraction: the win is instance isolation, not behavioral fakes. Stateless parsers, `AssetService`, `NotificationService`, and `LiveReloadClient` are unaffected and keep plain `static let shared`.
