import Foundation

/// Sparse key-path store backing Config Editor v2. Wraps a Hugo config's parsed
/// dictionary with dot-joined access. Presence is structural - a key is present iff it
/// exists in the dictionary - so sparse serialization falls out of the model rather
/// than being policed by convention.
///
/// Per the per-keystroke contract (CLAUDE.md), the raw blob (`root`) must never be an
/// observation dependency; `version` is the only observable signal.
@Observable
final class ConfigValueStore {

    /// The raw parsed config. NOT an observation dependency — mirrors
    /// FileCacheManager's rule that big mutable blobs must never be one.
    @ObservationIgnored
    private var root: [String: Any]

    /// The only observable signal. Bumped by every call to `set`, `remove`,
    /// or `replaceSubtree`, regardless of whether the resulting tree differs
    /// from before (these are the store's declared mutating operations).
    private(set) var version: Int = 0

    /// Root-level key order: document order at parse time, then append-on-new
    /// / drop-on-remove (CONFIG-SCHEMA-SPEC §2.7). Not an observation
    /// dependency — it changes only alongside `root`, and consumers that care
    /// (serializers) read it off the critical mutation path, not per keystroke.
    @ObservationIgnored
    private(set) var orderedRootKeys: [String]

    /// - Parameters:
    ///   - root: the parsed config dictionary. Normalized recursively here, since Yams
    ///     returns `[AnyHashable: Any]` for nested mappings, which can't serialize back.
    ///   - orderedRootKeys: document order, captured by the parser before the ordered
    ///     source collapsed into an unordered dictionary. The sorted fallback exists
    ///     because dictionary iteration order varies per launch and made tests flake.
    init(root: [String: Any], orderedRootKeys: [String]? = nil) {
        let normalized = SerializationHelper.normalizeForSerialization(root) as? [String: Any] ?? root
        self.root = normalized
        self.orderedRootKeys = Self.reconcile(order: orderedRootKeys, with: normalized)
    }

    /// The provided order filtered to keys actually present, plus any present
    /// keys the order missed (appended sorted). nil order → sorted keys.
    private static func reconcile(order: [String]?, with dict: [String: Any]) -> [String] {
        guard let order else { return dict.keys.sorted() }
        let known = order.filter { dict[$0] != nil }
        let remaining = dict.keys.filter { !order.contains($0) }.sorted()
        return known + remaining
    }

    // MARK: - Path access

    /// Split a dot-joined key path into segments.
    private static func segments(for path: String) -> [String] {
        path.components(separatedBy: ".")
    }

    /// Read the raw value at a key path. Never mutates.
    func value(at path: String) -> Any? {
        let segments = Self.segments(for: path)
        guard let first = segments.first else { return nil }
        var current: Any? = root[first]
        for segment in segments.dropFirst() {
            guard let dict = current as? [String: Any] else { return nil }
            current = dict[segment]
        }
        return current
    }

    /// Presence is "key exists in `root`" — nothing else.
    func isPresent(_ path: String) -> Bool {
        value(at: path) != nil
    }

    /// Set a value at a key path, creating intermediate dictionaries as needed.
    func set(_ value: Any, at path: String) {
        let segments = Self.segments(for: path)
        guard let first = segments.first else { return }

        setValue(value, at: segments, in: &root)
        syncOrderedRootKeys(after: first)
        version += 1
    }

    /// Remove the value at a key path, pruning now-empty intermediate
    /// dictionaries back up toward the root.
    func remove(at path: String) {
        let segments = Self.segments(for: path)
        guard let first = segments.first else { return }

        removeValue(at: segments, from: &root)
        syncOrderedRootKeys(after: first)
        version += 1
    }

    /// The dictionary at a key path, if present and dictionary-shaped.
    func subtree(_ path: String) -> [String: Any]? {
        value(at: path) as? [String: Any]
    }

    /// Replace the whole dictionary at a key path (recursive editors write
    /// back through this rather than diffing individual leaf keys).
    func replaceSubtree(_ path: String, with newValue: [String: Any]) {
        set(newValue, at: path)
    }

    /// A snapshot of the root dictionary, for serialization.
    func snapshotRoot() -> [String: Any] {
        root
    }

    /// Replace the entire root dictionary — e.g. a Raw→Form re-parse, where
    /// the whole document was re-read from scratch and the old tree is
    /// meaningless to diff against. Resets `orderedRootKeys` to the new
    /// document's order, same as `init`.
    func replaceRoot(with newRoot: [String: Any], orderedRootKeys: [String]? = nil) {
        let normalized = SerializationHelper.normalizeForSerialization(newRoot) as? [String: Any] ?? newRoot
        root = normalized
        self.orderedRootKeys = Self.reconcile(order: orderedRootKeys, with: normalized)
        version += 1
    }

    // MARK: - Mutation helpers

    private func setValue(_ value: Any, at segments: [String], in dict: inout [String: Any]) {
        guard let first = segments.first else { return }
        if segments.count == 1 {
            dict[first] = value
            return
        }
        var nested = (dict[first] as? [String: Any]) ?? [:]
        setValue(value, at: Array(segments.dropFirst()), in: &nested)
        dict[first] = nested
    }

    /// Removes the value at `segments` from `dict`, pruning any nested
    /// dictionary that becomes empty as a result. Returns whether anything
    /// was actually removed (used only internally; the public API doesn't
    /// need to distinguish a no-op remove from a real one).
    @discardableResult
    private func removeValue(at segments: [String], from dict: inout [String: Any]) -> Bool {
        guard let first = segments.first else { return false }
        if segments.count == 1 {
            return dict.removeValue(forKey: first) != nil
        }
        guard var nested = dict[first] as? [String: Any] else { return false }
        let removed = removeValue(at: Array(segments.dropFirst()), from: &nested)
        guard removed else { return false }
        if nested.isEmpty {
            dict.removeValue(forKey: first)
        } else {
            dict[first] = nested
        }
        return true
    }

    /// Keeps `orderedRootKeys` in sync with `root`'s top-level key set after
    /// a mutation that touched `rootKey`: append if newly present, drop if
    /// no longer present, leave untouched (no reordering) otherwise.
    private func syncOrderedRootKeys(after rootKey: String) {
        if root[rootKey] != nil {
            if !orderedRootKeys.contains(rootKey) {
                orderedRootKeys.append(rootKey)
            }
        } else {
            orderedRootKeys.removeAll { $0 == rootKey }
        }
    }

    // MARK: - Lenient typed reads
    //
    // "Lenient reads, strict writes": Hugo weak-decodes config values, so reads accept
    // the shapes Hugo would. Writes store the canonical type the caller passes in -
    // normalizing sloppy types is the caller's job, not the store's.

    /// Accepts `Bool`, `"true"`/`"false"` (case-insensitive), or `0`/`1` `Int`.
    func boolValue(_ path: String) -> Bool? {
        guard let raw = value(at: path) else { return nil }
        if let bool = raw as? Bool { return bool }
        if let string = raw as? String {
            switch string.lowercased() {
            case "true": return true
            case "false": return false
            default: return nil
            }
        }
        if let int = raw as? Int {
            if int == 0 { return false }
            if int == 1 { return true }
            return nil
        }
        return nil
    }

    /// Accepts `Int`, integral `Double`, or a numeric `String`.
    func intValue(_ path: String) -> Int? {
        guard let raw = value(at: path) else { return nil }
        if let int = raw as? Int { return int }
        if let double = raw as? Double, double.truncatingRemainder(dividingBy: 1) == 0 {
            return Int(double)
        }
        if let string = raw as? String, let int = Int(string) { return int }
        return nil
    }

    /// Accepts `Double`, `Int`, or a numeric `String`.
    func doubleValue(_ path: String) -> Double? {
        guard let raw = value(at: path) else { return nil }
        if let double = raw as? Double { return double }
        if let int = raw as? Int { return Double(int) }
        if let string = raw as? String, let double = Double(string) { return double }
        return nil
    }

    /// Accepts `String`, or the stringified form of `Bool`/`Int`/`Double`.
    func stringValue(_ path: String) -> String? {
        guard let raw = value(at: path) else { return nil }
        if let string = raw as? String { return string }
        if let bool = raw as? Bool { return bool ? "true" : "false" }
        if let int = raw as? Int { return String(int) }
        if let double = raw as? Double { return String(double) }
        return nil
    }

    /// Accepts `[String]`, a `[Any]` whose elements are all `String`, or a
    /// single `String` (wrapped as a one-element array).
    func stringArrayValue(_ path: String) -> [String]? {
        guard let raw = value(at: path) else { return nil }
        if let strings = raw as? [String] { return strings }
        if let array = raw as? [Any] {
            var result: [String] = []
            result.reserveCapacity(array.count)
            for element in array {
                guard let string = element as? String else { return nil }
                result.append(string)
            }
            return result
        }
        if let string = raw as? String { return [string] }
        return nil
    }
}
