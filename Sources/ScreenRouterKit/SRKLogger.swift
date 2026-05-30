public enum SRKDebugMode: Sendable {
    case disabled
    case minimal
    case verbose
}

enum SRKLogLevel: Sendable {
    case error, warning, info, debug, network

    nonisolated var icon: String {
        switch self {
        case .error:   "❌"
        case .warning: "⚠️"
        case .info:    "✅"
        case .debug:   "🔍"
        case .network: "🌐"
        }
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.error, .error), (.warning, .warning), (.info, .info),
             (.debug, .debug), (.network, .network): true
        default: false
        }
    }
}

extension SRKLogLevel: Equatable {}

// String raw value removed — synthesised rawValue would be @MainActor.
// logKey callers use only dot-syntax cases, never string init.
enum SRKMinimalTag: Sendable {
    case finalURL, fcmFirst, fcmRefresh, deviceID, appsFields, error
    case idfa, installType, syncResult

    nonisolated var rawValue: String {
        switch self {
        case .finalURL:     "FINAL_URL"
        case .fcmFirst:     "FCM_FIRST"
        case .fcmRefresh:   "FCM_REFRESH"
        case .deviceID:     "DEVICE_ID"
        case .appsFields:   "APPS_FIELDS"
        case .error:        "ERROR"
        case .idfa:         "IDFA"
        case .installType:  "AF_INSTALL_TYPE"
        case .syncResult:   "SYNC_RESULT"
        }
    }
}

enum SRKLogger {

    nonisolated(unsafe) static var mode: SRKDebugMode = .disabled

    nonisolated static func log(
        _ level: SRKLogLevel,
        _ message: String,
        file: String = #fileID
    ) {
        switch mode {
        case .disabled:
            return
        case .minimal:
            guard level == .error else { return }
            print("[SRK] \(level.icon) \(message)")
        case .verbose:
            let filename = file.split(separator: "/").last.map(String.init) ?? file
            print("[SRK][\(level.icon)][\(filename)] \(message)")
        }
    }

    nonisolated static func logKey(_ tag: SRKMinimalTag, _ message: String, file: String = #fileID) {
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
