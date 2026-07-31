import Foundation
import TOMLKit

/// Helper for TOML value conversion and table manipulation
/// Provides reusable utilities for working with TOML data in parsers
enum TOMLHelper {

    // MARK: - Conversion

    static func convertTOMLToDict(_ table: TOMLTable) -> [String: Any] {
        var result: [String: Any] = [:]
        for key in table.keys {
            if let converted = convertTOMLValue(table[key]) {
                result[key] = converted
            }
        }
        return result
    }

    /// Unwraps TOMLValue, recursing through nested tables and arrays.
    static func convertTOMLValue(_ value: Any?) -> Any? {
        guard let value = value else { return nil }

        // Handle TOMLValue wrapper type
        if let tomlValue = value as? TOMLValue {
            if let str = tomlValue.string {
                return str
            }
            if let bool = tomlValue.bool {
                return bool
            }
            if let int = tomlValue.int {
                return Int(int)
            }
            if let double = tomlValue.double {
                return double
            }
            if let date = tomlValue.date {
                return "\(date)"
            }
            if let time = tomlValue.time {
                return "\(time)"
            }
            if let dateTime = tomlValue.dateTime {
                return "\(dateTime)"
            }
            if let array = tomlValue.array {
                return array.compactMap { convertTOMLValue($0) }
            }
            if let table = tomlValue.table {
                return convertTOMLToDict(table)
            }
        }

        // Handle nested tables
        if let table = value as? TOMLTable {
            return convertTOMLToDict(table)
        }

        // Handle arrays
        if let array = value as? [Any] {
            return array.compactMap { convertTOMLValue($0) }
        }

        // Handle native Swift types (fallback)
        if let stringValue = value as? String {
            return stringValue
        }
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let intValue = value as? Int {
            return intValue
        }
        if let int64Value = value as? Int64 {
            return Int(int64Value)
        }
        if let doubleValue = value as? Double {
            return doubleValue
        }

        // Fallback for any other type
        return value
    }

    // MARK: - Text Serialization

    /// Serialize to TOML text, trailing newline included.
    ///
    /// `rootKeyOrder` (e.g. `ConfigValueStore.orderedRootKeys`) is honored only at the root
    /// table, per CONFIG-SCHEMA-SPEC §2.7; nested tables and the `nil` case sort alphabetically.
    static func serializeToTOML(_ dictionary: [String: Any], rootKeyOrder: [String]? = nil) -> String {
        var lines: [String] = []
        serializeTOMLTable(dictionary, path: [], lines: &lines, rootKeyOrder: rootKeyOrder)
        return lines.joined(separator: "\n") + "\n"
    }

    /// `path` is the current key path - `["menu", "main"]` emits `[menu.main]`.
    /// `rootKeyOrder` applies only when `path` is empty.
    static func serializeTOMLTable(_ dict: [String: Any], path: [String], lines: inout [String], rootKeyOrder: [String]? = nil) {
        var simpleValues: [(String, Any)] = []
        var nestedTables: [(String, [String: Any])] = []
        var arrayOfTables: [(String, [[String: Any]])] = []

        let orderedKeys: [String]
        if path.isEmpty, let rootKeyOrder {
            let known = rootKeyOrder.filter { dict[$0] != nil }
            let remaining = dict.keys.filter { !rootKeyOrder.contains($0) }.sorted()
            orderedKeys = known + remaining
        } else {
            orderedKeys = dict.keys.sorted()
        }

        for key in orderedKeys {
            guard let value = dict[key] else { continue }
            if let arrayValue = value as? [Any] {
                if let dictArray = arrayValue as? [[String: Any]], !dictArray.isEmpty {
                    arrayOfTables.append((key, dictArray))
                } else {
                    simpleValues.append((key, value))
                }
            } else if let dictValue = value as? [String: Any] {
                nestedTables.append((key, dictValue))
            } else {
                simpleValues.append((key, value))
            }
        }

        // Write table header if not at root and have simple values
        if !path.isEmpty && !simpleValues.isEmpty {
            if !lines.isEmpty {
                lines.append("")
            }
            lines.append("[\(path.joined(separator: "."))]")
        }

        // Write simple values
        for (key, value) in simpleValues {
            lines.append(formatTOMLValue(key: key, value: value))
        }

        // Write nested tables
        for (key, nestedDict) in nestedTables {
            serializeTOMLTable(nestedDict, path: path + [key], lines: &lines)
        }

        // Write arrays of tables using [[table.name]] syntax
        for (key, dictArray) in arrayOfTables {
            let tablePath = path + [key]
            let tablePathStr = tablePath.joined(separator: ".")

            for tableDict in dictArray {
                if !lines.isEmpty {
                    lines.append("")
                }
                lines.append("[[\(tablePathStr)]]")

                // Scalars must all precede any nested [table.header] line —
                // anything emitted after a header re-parses as a member of
                // that nested table, not of this array element
                let sortedItems = tableDict.sorted(by: { $0.key < $1.key })
                for (itemKey, itemValue) in sortedItems
                where !(itemValue is [String: Any]) && !(itemValue is [[String: Any]]) {
                    lines.append(formatTOMLValue(key: itemKey, value: itemValue))
                }
                for (itemKey, itemValue) in sortedItems {
                    if let nestedDict = itemValue as? [String: Any] {
                        serializeTOMLTable(nestedDict, path: tablePath + [itemKey], lines: &lines)
                    } else if let nestedArray = itemValue as? [[String: Any]] {
                        // Nested array of tables within array of tables
                        for nestedTableDict in nestedArray {
                            lines.append("")
                            lines.append("[[\(tablePathStr).\(itemKey)]]")
                            for (nk, nv) in nestedTableDict.sorted(by: { $0.key < $1.key }) {
                                lines.append(formatTOMLValue(key: nk, value: nv))
                            }
                        }
                    }
                }
            }
        }
    }

    /// Format a single TOML key-value pair
    static func formatTOMLValue(key: String, value: Any) -> String {
        if let stringValue = value as? String {
            let escaped = stringValue
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\(key) = \"\(escaped)\""
        } else if let boolValue = value as? Bool {
            return "\(key) = \(boolValue)"
        } else if let intValue = value as? Int {
            return "\(key) = \(intValue)"
        } else if let doubleValue = value as? Double {
            return "\(key) = \(doubleValue)"
        } else if let arrayValue = value as? [Any] {
            let formatted = arrayValue.map { formatTOMLArrayElement($0) }.joined(separator: ", ")
            return "\(key) = [\(formatted)]"
        }
        return "\(key) = \"\(String(describing: value))\""
    }

    /// Format a single element within a TOML array
    static func formatTOMLArrayElement(_ value: Any) -> String {
        if let stringValue = value as? String {
            let escaped = stringValue
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        } else if let boolValue = value as? Bool {
            return "\(boolValue)"
        } else if let intValue = value as? Int {
            return "\(intValue)"
        } else if let doubleValue = value as? Double {
            return "\(doubleValue)"
        }
        return "\"\(String(describing: value))\""
    }

    // MARK: - Table Serialization

    /// Converts the Swift value to its TOML counterpart on the way in.
    static func addToTOMLTable(key: String, value: Any, table: TOMLTable) {
        if let stringValue = value as? String {
            table[key] = stringValue
        } else if let intValue = value as? Int {
            table[key] = intValue
        } else if let doubleValue = value as? Double {
            table[key] = doubleValue
        } else if let boolValue = value as? Bool {
            table[key] = boolValue
        } else if let arrayValue = value as? [String] {
            table[key] = arrayValue
        } else if let dictValue = value as? [String: Any] {
            let subTable = TOMLTable()
            for (subKey, subValue) in dictValue {
                addToTOMLTable(key: subKey, value: subValue, table: subTable)
            }
            table[key] = subTable
        } else {
            // Fallback: convert unknown types to string to prevent data loss
            table[key] = String(describing: value)
        }
    }

}
