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

/// Centralized logging service for consistent error reporting and debugging
final class Logger {
    static let shared = Logger()

    #if DEBUG
    var minLevel: LogLevel = .debug
    #else
    var minLevel: LogLevel = .warning
    #endif

    private let osLog = OSLog(subsystem: "com.victor.app", category: "general")

    private init() {}

    func debug(_ message: String, file: String = #file, line: Int = #line) {
        log(level: .debug, message: message, file: file, line: line)
    }

    func info(_ message: String, file: String = #file, line: Int = #line) {
        log(level: .info, message: message, file: file, line: line)
    }

    func warning(_ message: String, file: String = #file, line: Int = #line) {
        log(level: .warning, message: message, file: file, line: line)
    }

    func error(_ message: String, error: Error? = nil, file: String = #file, line: Int = #line) {
        let fullMessage = error != nil ? "\(message): \(error!.localizedDescription)" : message
        log(level: .error, message: fullMessage, file: file, line: line)
    }

    private func log(level: LogLevel, message: String, file: String, line: Int) {
        guard level >= minLevel else { return }

        let fileName = (file as NSString).lastPathComponent
        let prefix = "[\(level)] \(fileName):\(line)"

        #if DEBUG
        print("\(prefix) - \(message)")
        #endif

        os_log("%{public}@ - %{public}@", log: osLog, type: level.osLogType, prefix, message)
    }
}

private extension LogLevel {
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }
}
