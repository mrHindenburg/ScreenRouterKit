import Foundation


enum SRKLogger {

    /// Prints the INSTALL request-data table.
    nonisolated static func install(_ rows: [(String, String)]) {
        #if DEBUG
        print(render("INSTALL", rows), terminator: "")
        #endif
    }

    /// Prints the SYNC request-data table, skipping unchanged repeats.
    nonisolated static func sync(_ rows: [(String, String)]) {
        #if DEBUG
        let signature = rows.map { "\($0.0)=\($0.1)" }.joined(separator: "|")
        if lastSyncSignature == signature {
            print("\n╶╶╶ SYNC — no changes\n", terminator: "")
            return
        }
        lastSyncSignature = signature
        print(render("SYNC", rows), terminator: "")
        #endif
    }

    #if DEBUG
    // Last printed SYNC table signature — used to skip unchanged repeats.
    nonisolated(unsafe) private static var lastSyncSignature: String?

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
    #endif
}
