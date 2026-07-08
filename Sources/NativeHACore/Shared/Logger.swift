import Foundation

public enum LogLevel: String, Equatable {
    case debug
    case info
    case warning
    case error
}

public protocol Logger {
    func log(_ level: LogLevel, _ message: String, metadata: [String: String])
}

public extension Logger {
    func debug(_ message: String, metadata: [String: String] = [:]) {
        log(.debug, message, metadata: metadata)
    }

    func info(_ message: String, metadata: [String: String] = [:]) {
        log(.info, message, metadata: metadata)
    }

    func warning(_ message: String, metadata: [String: String] = [:]) {
        log(.warning, message, metadata: metadata)
    }

    func error(_ message: String, metadata: [String: String] = [:]) {
        log(.error, message, metadata: metadata)
    }
}

public struct ConsoleLogger: Logger {
    public init() {}

    public func log(_ level: LogLevel, _ message: String, metadata: [String: String] = [:]) {
        let metadataText = metadata.isEmpty ? "" : " \(metadata)"
        print("[NativeHA] [\(level.rawValue)] \(message)\(metadataText)")
    }
}
