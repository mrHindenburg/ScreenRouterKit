import Foundation

struct SRKSessionResponse: Decodable {
    let url: String
}

enum SRKAPIError: LocalizedError {
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

final class SRKNetworkManager: Sendable {

    private let config: SRKConfiguration

    init(config: SRKConfiguration) {
        self.config = config
    }

    func fetchRegister(
        fcmToken: String,
        deviceID: String,
        appsFlyerID: String
    ) async -> Result<SRKSessionResponse, SRKAPIError> {

        guard let url = URL(string: config.registerURL) else {
            SRKLogger.log(.error, "Register: invalid registerURL")
            return .failure(.invalidURL)
        }

        var body: [String: String] = [
            "bundle":    config.bundleID,
            "fcm_token": fcmToken,
            "device":    deviceID,
        ]

        if !appsFlyerID.isEmpty {
            body["appsFlyerId"] = appsFlyerID
        }

        SRKLogger.log(.network, "Register: POST \(config.registerURL)")
        SRKLogger.log(.network, "Register: bundle=\(config.bundleID) device=\(deviceID) fcm=\(fcmToken) af=\(appsFlyerID.isEmpty ? "none" : String(appsFlyerID))")

        return await performRequest(url: url, body: body, tag: "Install")
    }

    func refresh(
        fcmToken: String,
        deviceID: String,
        appsFlyerID: String
    ) async {

        guard let url = URL(string: config.syncURL) else {
            SRKLogger.log(.error, "Sync: invalid syncURL")
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

        SRKLogger.log(.network, "Sync: POST \(config.syncURL)")

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                SRKLogger.log(.error, "Sync: invalid response")
                return
            }
            SRKLogger.log(.network, "Sync: status \(http.statusCode)")
            if let text = String(data: data, encoding: .utf8) {
                SRKLogger.log(.network, "Sync: response — \(text)")
            }
            if (200...299).contains(http.statusCode) {
                SRKLogger.log(.info, "Sync: success")
            } else {
                SRKLogger.log(.error, "Sync: server error \(http.statusCode)")
            }
        } catch {
            SRKLogger.log(.error, "Sync: error — \(error.localizedDescription)")
        }
    }

    private func performRequest<T: Decodable>(
        url: URL,
        body: [String: String],
        tag: String
    ) async -> Result<T, SRKAPIError> {

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

            SRKLogger.log(.network, "\(tag): status \(http.statusCode)")

            if let text = String(data: data, encoding: .utf8) {
                SRKLogger.log(.network, "\(tag): response — \(text)")
            }

            guard (200...299).contains(http.statusCode) else {
                return .failure(.serverError(http.statusCode))
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
