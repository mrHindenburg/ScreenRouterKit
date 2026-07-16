import Foundation

nonisolated public enum SRKDebugMode: Sendable {
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

enum SRKLogger {

    nonisolated(unsafe) static var mode: SRKDebugMode = .disabled

    // Whether the current init configured AppsFlyer. When false, `af(...)` logs are
    // suppressed entirely so AppsFlyer-related noise never appears in non-tracking scenarios.
    nonisolated(unsafe) static var appsFlyerEnabled: Bool = false

    // Last printed table signature per id — used to skip unchanged tables.
    nonisolated(unsafe) private static var lastTableSignature: [String: String] = [:]

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

    nonisolated static func key(
        _ message: String,
        file: String = #fileID
    ) {
        switch mode {
        case .disabled:
            return
        case .minimal:
            print("[SRK] 🔑 \(message)")
        case .verbose:
            let filename = file.split(separator: "/").last.map(String.init) ?? file
            print("[SRK][🔑][\(filename)] \(message)")
        }
    }

    nonisolated static func af(
        _ level: SRKLogLevel,
        _ message: String,
        file: String = #fileID
    ) {
        guard appsFlyerEnabled else { return }
        log(level, message, file: file)
    }

    /// Prints a compact, aligned key/value table. Visible in `.minimal` and `.verbose`.
    nonisolated static func table(_ title: String, _ rows: [(String, String)]) {
        guard mode != .disabled else { return }
        print(render(title, rows), terminator: "")
    }

    nonisolated static func tableIfChanged(_ title: String, _ rows: [(String, String)], id: String) {
        guard mode != .disabled else { return }
        let signature = rows.map { "\($0.0)=\($0.1)" }.joined(separator: "|")
        if lastTableSignature[id] == signature {
            print("\n╶╶╶ \(title) — no changes\n", terminator: "")
            return
        }
        lastTableSignature[id] = signature
        print(render(title, rows), terminator: "")
    }

    private nonisolated static func render(_ title: String, _ rows: [(String, String)]) -> String {
        let width = 44
        let keyWidth = rows.map { $0.0.count }.max() ?? 0
        let header = "─── \(title) "
        let topRule = header + String(repeating: "─", count: max(3, width - header.count))
        let bottomRule = String(repeating: "─", count: width)

        var out = "\n\(topRule)\n"
        for (key, value) in rows {
            let paddedKey = key.padding(toLength: keyWidth, withPad: " ", startingAt: 0)
            out += "  \(paddedKey)  \(value)\n"
        }
        out += "\(bottomRule)\n"
        return out
    }
}
