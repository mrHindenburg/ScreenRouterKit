import Foundation

struct SRKSessionResponse: Decodable {
    let url: String
}

enum SRKAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(Int, String?)
    case decodingError
    case noNetwork
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:         return "Invalid URL"
        case .invalidResponse:    return "Invalid server response"
        case .serverError(let c, let body):
            if let body, !body.isEmpty {
                return "Server error: \(c) — \(body)"
            }
            return "Server error: \(c)"
        case .decodingError:      return "Response decoding error"
        case .noNetwork:          return "No internet connection"
        case .unknown(let e):     return e.localizedDescription
        }
    }
}

final class SRKNetworkManager: Sendable {

    private let config: SRKConfiguration

    init(config: SRKConfiguration) {
        self.config = config
    }

    func fetchRegister(
        fcmToken: String,
        deviceID: String?,
        appsFlyerID: String
    ) async -> Result<SRKSessionResponse, SRKAPIError> {

        guard let url = URL(string: config.registerURL) else {
            SRKLogger.log(.error, "Register: invalid registerURL")
            return .failure(.invalidURL)
        }

        let id: String = UUID().uuidString
        var body: [String: Any] = [
            "uuid": id,
            "bundle":    config.appId,
            "fcm_token": fcmToken,
        ]

        if let deviceID, !deviceID.isEmpty {
            body["device"] = deviceID
        }

        if !appsFlyerID.isEmpty {
            body["appsFlyerId"] = appsFlyerID
        }

        if let extra = config.extraInstallFieldsProvider?() {
            for (k, v) in extra { body[k] = v }
        }

        return await performRequest(url: url, body: body, tag: "INSTALL")
    }

    func refresh(
        fcmToken: String,
        deviceID: String?,
        appsFlyerID: String
    ) async {

        guard let url = URL(string: config.syncURL) else {
            SRKLogger.log(.error, "Sync: invalid syncURL")
            return
        }

        var body: [String: String] = [
            "bundle":    config.appId,
            "fcm_token": fcmToken,
        ]

        if let deviceID, !deviceID.isEmpty {
            body["device"] = deviceID
        }

        if !appsFlyerID.isEmpty {
            body["appsFlyerId"] = appsFlyerID
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                SRKLogger.log(.error, "Refresh: invalid response")
                return
            }

            let rows = Self.bodyRows(body as [String: Any])
            SRKLogger.tableIfChanged("REFRESH", rows, id: "refresh")

            if !(200...299).contains(http.statusCode) {
                let responseBody = Self.responseBodyString(data)
                SRKLogger.log(.error, "Refresh: server error \(http.statusCode) — response: \(responseBody ?? "—")")
            }
        } catch {
            SRKLogger.log(.error, "Refresh: error — \(error.localizedDescription)")
        }
    }

    /// Builds ordered rows for the INSTALL / REFRESH log tables from a request body.
    /// The log is intentionally trimmed to a short whitelist; the request body still
    /// sends everything, only the printed table is reduced.
    private static func bodyRows(_ body: [String: Any]) -> [(String, String)] {
        func disp(_ v: Any) -> String {
            let s = String(describing: v)
            return s.isEmpty ? "—" : s
        }

        let appsInfo = body["appsInfo"] as? [String: Any] ?? [:]
        func value(_ key: String) -> Any? { body[key] ?? appsInfo[key] }

        var rows: [(String, String)] = []
        for key in ["device", "fcm_token", "af_status", "language", "timezone", "install_time", "idfa"] {
            if let v = value(key) { rows.append((key, disp(v))) }
        }
        if rows.first(where: { $0.0 == "device" }) == nil {
            rows.insert(("device", "—"), at: 0)
        }
        return rows
    }

    /// Converts a raw error-response body into a printable string for logs / SRKAPIError.
    private static func responseBodyString(_ data: Data) -> String? {
        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return nil }
        return text
    }

    private func performRequest<T: Decodable>(
        url: URL,
        body: [String: Any],
        tag: String
    ) async -> Result<T, SRKAPIError> {

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            return .failure(.unknown(error))
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                return .failure(.invalidResponse)
            }

            SRKLogger.table(tag, Self.bodyRows(body))

            guard (200...299).contains(http.statusCode) else {
                let responseBody = Self.responseBodyString(data)
                SRKLogger.log(.error, "\(tag): server error \(http.statusCode) — response: \(responseBody ?? "—")")
                return .failure(.serverError(http.statusCode, responseBody))
            }

            if http.statusCode == 204 || data.isEmpty {
                SRKLogger.log(.info, "\(tag): 204 / empty body → main")
                let emptyJSON = Data("{\"url\":\"\"}".utf8)
                if let result = try? JSONDecoder().decode(T.self, from: emptyJSON) {
                    return .success(result)
                }
            }

            do {
                return .success(try JSONDecoder().decode(T.self, from: data))
            } catch {
                SRKLogger.log(.error, "\(tag): decoding error — \(error)")
                return .failure(.decodingError)
            }

        } catch let urlError as URLError {
            if urlError.code == .notConnectedToInternet
                || urlError.code == .networkConnectionLost {
                return .failure(.noNetwork)
            }
            return .failure(.unknown(urlError))
        } catch {
            return .failure(.unknown(error))
        }
    }
}
