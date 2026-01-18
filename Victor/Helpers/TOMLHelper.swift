import Foundation
import TOMLKit

/// Helper for TOML value conversion and table manipulation
/// Provides reusable utilities for working with TOML data in parsers
enum TOMLHelper {

    // MARK: - Conversion

    /// Convert TOMLTable to dictionary
    /// - Parameter table: The TOML table to convert
    /// - Returns: Dictionary with converted values
    static func convertTOMLToDict(_ table: TOMLTable) -> [String: Any] {
        var result: [String: Any] = [:]
        for key in table.keys {
            if let converted = convertTOMLValue(table[key]) {
                result[key] = converted
            }
        }
        return result
    }

    /// Convert TOML value to native Swift type
    /// Handles TOMLValue wrappers, nested tables, and arrays recursively
    /// - Parameter value: The TOML value to convert
    /// - Returns: Converted Swift value (String, Bool, Int, Double, Array, Dictionary, etc.)
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

    // MARK: - Serialization

    /// Add a value to a TOML table
    /// Handles conversion of Swift types to TOML values
    /// - Parameters:
    ///   - key: The key for the value
    ///   - value: The value to add
    ///   - table: The TOML table to add to
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
        }
        // Skip other types (incompatible with TOML)
    }

}
