import Foundation
import os

/// Log severity levels
enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Centralized logging facade over `os.Logger`. `minLevel` is assigned once via `#if DEBUG`
/// and never reassigned, so it's a `let` - which, with `os.Logger` being `Sendable`, makes
/// this type safe across actor boundaries without `@unchecked`.
///
/// `category` defaults to `"general"`, so the ~109 existing call sites are unaffected.
final class Logger: Sendable {
    static let shared = Logger()

    #if DEBUG
    let minLevel: LogLevel = .debug
    #else
    let minLevel: LogLevel = .warning
    #endif

    private static let subsystem = "com.victor.app"

    /// Default category for call sites that don't specify one - matches the single
    /// `"general"` category the old `OSLog` engine always used.
    static let defaultCategory = "general"

    private init() {}

    func debug(_ message: String, category: String = Logger.defaultCategory, file: String = #file, line: Int = #line) {
        log(level: .debug, message: message, category: category, file: file, line: line)
    }

    func info(_ message: String, category: String = Logger.defaultCategory, file: String = #file, line: Int = #line) {
        log(level: .info, message: message, category: category, file: file, line: line)
    }

    func warning(_ message: String, category: String = Logger.defaultCategory, file: String = #file, line: Int = #line) {
        log(level: .warning, message: message, category: category, file: file, line: line)
    }

    func error(_ message: String, error: Error? = nil, category: String = Logger.defaultCategory, file: String = #file, line: Int = #line) {
        let fullMessage = error != nil ? "\(message): \(error!.localizedDescription)" : message
        log(level: .error, message: fullMessage, category: category, file: file, line: line)
    }

    private func log(level: LogLevel, message: String, category: String, file: String, line: Int) {
        guard level >= minLevel else { return }

        let fileName = (file as NSString).lastPathComponent
        let prefix = "[\(level)] \(fileName):\(line)"

        #if DEBUG
        print("\(prefix) - \(message)")
        #endif

        // `os.Logger` values are cheap, immutable, plain-data wrappers around the
        // subsystem/category pair - no caching needed, unlike the old class-based `OSLog`.
        let osLogger = os.Logger(subsystem: Self.subsystem, category: category)

        // Explicit `privacy: .public` per interpolated value - the direct replacement
        // for the old `os_log("%{public}@ - %{public}@", ...)` format string. Both
        // `prefix` (source location) and `message` are internal diagnostic strings with
        // no user content, so `.public` (unredacted in Console.app) is correct here,
        // same as before.
        switch level {
        case .debug:
            osLogger.debug("\(prefix, privacy: .public) - \(message, privacy: .public)")
        case .info:
            osLogger.info("\(prefix, privacy: .public) - \(message, privacy: .public)")
        case .warning:
            osLogger.warning("\(prefix, privacy: .public) - \(message, privacy: .public)")
        case .error:
            osLogger.error("\(prefix, privacy: .public) - \(message, privacy: .public)")
        }
    }
}
