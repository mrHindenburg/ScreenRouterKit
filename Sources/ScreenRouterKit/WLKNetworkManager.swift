// WLKNetworkManager.swift
// ScreenRouterKit


import Foundation

// MARK: - Response

struct WLKInstallResponse: Decodable {
    let url: String
}

// MARK: - Errors

enum WLKAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(Int)
    case decodingError
    case noNetwork
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:         return "Invalid URL"
        case .invalidResponse:    return "Invalid server response"
        case .serverError(let c): return "Server error: \(c)"
        case .decodingError:      return "Response decoding error"
        case .noNetwork:          return "No internet connection"
        case .unknown(let e):     return e.localizedDescription
        }
    }
}

// MARK: - Network Manager

final class WLKNetworkManager: Sendable {

    private let config: WLKConfiguration

    init(config: WLKConfiguration) {
        self.config = config
    }

    // MARK: - Install

    func fetchInstall(
        fcmToken: String,
        deviceID: String,
        appsFlyerID: String  // empty string for variant A
    ) async -> Result<WLKInstallResponse, WLKAPIError> {

        guard let url = URL(string: config.installURL) else {
            WLKLogger.log(.error, "Install: invalid installURL")
            return .failure(.invalidURL)
        }

        var body: [String: String] = [
            "bundle":    config.bundleID,
            "fcm_token": fcmToken,
            "device":    deviceID,
        ]

        // Include appsFlyerId only if available
        if !appsFlyerID.isEmpty {
            body["appsFlyerId"] = appsFlyerID
        }

        WLKLogger.log(.network, "Install: POST \(config.installURL)")
        WLKLogger.log(.network, "Install: bundle=\(config.bundleID) device=\(deviceID)... fcm=\(fcmToken)... af=\(appsFlyerID.isEmpty ? "none" : String(appsFlyerID))")

        return await performRequest(url: url, body: body, tag: "Install")
    }

    // MARK: - Refresh

    func refresh(
        fcmToken: String,
        deviceID: String,
        appsFlyerID: String
    ) async {

        guard let url = URL(string: config.refreshURL) else {
            WLKLogger.log(.error, "Refresh: invalid refreshURL")
            return
        }

        var body: [String: String] = [
            "bundle":    config.bundleID,
            "fcm_token": fcmToken,
            "device":    deviceID,
        ]

        if !appsFlyerID.isEmpty {
            body["appsFlyerId"] = appsFlyerID
        }

        WLKLogger.log(.network, "Refresh: POST \(config.refreshURL)")

        let result: Result<WLKInstallResponse, WLKAPIError> = await performRequest(
            url: url, body: body, tag: "Refresh"
        )

        switch result {
        case .success:
            WLKLogger.log(.info, "Refresh: success")
        case .failure(let error):
            WLKLogger.log(.error, "Refresh: error — \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func performRequest<T: Decodable>(
        url: URL,
        body: [String: String],
        tag: String
    ) async -> Result<T, WLKAPIError> {

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            return .failure(.unknown(error))
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                return .failure(.invalidResponse)
            }

            WLKLogger.log(.network, "\(tag): status \(http.statusCode)")

            if let text = String(data: data, encoding: .utf8) {
                WLKLogger.log(.network, "\(tag): response — \(text)")
            }

            guard (200...299).contains(http.statusCode) else {
                return .failure(.serverError(http.statusCode))
            }

            // 204 No Content or empty body — valid success with no URL → show main
            if http.statusCode == 204 || data.isEmpty {
                WLKLogger.log(.info, "\(tag): 204 / empty body → main")
                let emptyJSON = Data("{\"url\":\"\"}".utf8)
                if let result = try? JSONDecoder().decode(T.self, from: emptyJSON) {
                    return .success(result)
                }
            }

            do {
                return .success(try JSONDecoder().decode(T.self, from: data))
            } catch {
                WLKLogger.log(.error, "\(tag): decoding error — \(error)")
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
