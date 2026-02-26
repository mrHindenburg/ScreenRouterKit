// SRKLogger.swift
// ScreenRouterKit

import Foundation

// MARK: - Debug Mode

public enum SRKDebugMode: Sendable {
    /// Silent — for production
    case disabled
    /// Key events only: errors, final URL, FCM tokens, device ID
    case minimal
    /// Full lifecycle: ATT, Push, API, navigation — for development
    case verbose
}

// MARK: - Log Level

enum SRKLogLevel: Sendable {
    case error
    case warning
    case info
    case debug
    case network

    var icon: String {
        switch self {
        case .error:   return "❌"
        case .warning: return "⚠️"
        case .info:    return "✅"
        case .debug:   return "🔍"
        case .network: return "🌐"
        }
    }
}

// MARK: - Minimal Event Tag
// Used to filter output in .minimal mode to key events only

enum SRKMinimalTag: String {
    case finalURL    = "FINAL_URL"
    case fcmFirst    = "FCM_FIRST"
    case fcmRefresh  = "FCM_REFRESH"
    case deviceID    = "DEVICE_ID"
    case error       = "ERROR"
}

// MARK: - Logger

enum SRKLogger {

    static var mode: SRKDebugMode = .disabled

    // MARK: - General log

    static func log(
        _ level: SRKLogLevel,
        _ message: String,
        file: String = #fileID
    ) {
        switch mode {
        case .disabled:
            return

        case .minimal:
            // minimal — errors only via general log
            guard level == .error else { return }
            print("[SRK] \(level.icon) \(message)")

        case .verbose:
            let filename = file.split(separator: "/").last.map(String.init) ?? file
            print("[SRK][\(level.icon)][\(filename)] \(message)")
        }
    }

    // MARK: - Key events (printed in minimal and verbose)

    static func logKey(_ tag: SRKMinimalTag, _ message: String, file: String = #fileID) {
        switch mode {
        case .disabled:
            return

        case .minimal:
            print("[SRK] [\(tag.rawValue)] \(message)")

        case .verbose:
            let filename = file.split(separator: "/").last.map(String.init) ?? file
            print("[SRK][🔑][\(filename)][\(tag.rawValue)] \(message)")
        }
    }
}
