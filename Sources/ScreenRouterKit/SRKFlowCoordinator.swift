// SRKFlowCoordinator.swift
// ScreenRouterKit

import Foundation
import Network

// MARK: - Route Lock

enum SRKRoute: String {
    case main
    case web
}

// MARK: - Coordinator

@MainActor
final class SRKFlowCoordinator {

    // MARK: Dependencies

    private let config: SRKConfiguration
    private let attGate: SRKATTGate
    private let pushGate: SRKPushGate
    private let networkManager: SRKNetworkManager

    // MARK: State

    weak var viewModel: SRKViewModel?

    private var resolved        = false
    private var refreshInFlight = false
    private var lastRefreshFCM: String?

    // MARK: UserDefaults Keys

    private let routeLockKey     = "srk.flow.lock"
    private let storedURLKey     = "srk.flow.url"
    private let sessionDoneKey   = "srk.session.done"
    private let sessionFCMKey    = "srk.session.fcm"
    private let sessionDeviceKey = "srk.session.device"
    private let attAuthorizedKey = "srk.att.authorized"
    private let stableUUIDKey    = "srk.stable.uuid"

    // MARK: Init

    init(config: SRKConfiguration) {
        self.config         = config
        self.attGate        = SRKATTGate(handling: config.attHandling)
        self.pushGate       = SRKPushGate(enabled: config.pushEnabled)
        self.networkManager = SRKNetworkManager(config: config)
    }

    // MARK: - Start

    func start() {
        guard !resolved else {
            SRKLogger.log(.debug, "Coordinator: already resolved — start() ignored")
            return
        }

        SRKLogger.log(.debug, "Coordinator: start()")

        // Subsequent start — read saved lock, skip API call
        if let lock = loadRouteLock() {
            SRKLogger.log(.info, "Coordinator: found lock=\(lock.rawValue)")
            applyRoute(lock, url: UserDefaults.standard.string(forKey: storedURLKey))
            resolved = true
            return
        }

        Task { await runPipeline() }
    }

    // MARK: - Pipeline

    private func runPipeline() async {
        SRKLogger.log(.debug, "Coordinator: pipeline start")
        viewModel?.setLoading()

        // ── 1. Network ───────────────────────────────────────────────────
        guard await waitForNetwork() else {
            SRKLogger.log(.info, "Coordinator: no network → main (no lock)")
            viewModel?.setMain()
            resolved = true
            return
        }

        // ── 2. ATT ────────────────────────────────────────────────────────
        // Variant A: library shows the ATT alert itself
        // Variant B: library waits for signal.complete() from host
        //            (host calls AppsFlyerLib.shared().start() between ATT and this point)
        SRKLogger.log(.debug, "Coordinator: step 2 — ATT")
        let attAuthorized = await attGate.requestIfNeeded()
        UserDefaults.standard.set(attAuthorized, forKey: attAuthorizedKey)
        SRKLogger.log(.info, "Coordinator: ATT authorized=\(attAuthorized)")

        // ── 3. Push + FCM ────────────────────────────────────────────────
        SRKLogger.log(.debug, "Coordinator: step 3 — Push + FCM")
        let fcmToken = await pushGate.requestAndCollect() ?? ""
        let fcmLog = fcmToken.isEmpty ? "(empty)" : String(fcmToken)
        SRKLogger.logKey(.fcmFirst, "fcm=\(fcmLog)")

        // ── 4. Device ID ─────────────────────────────────────────────────
        let deviceID = resolveDeviceID(attAuthorized: attAuthorized)
        SRKLogger.log(.debug, "Coordinator: deviceID=\(deviceID)")
        SRKLogger.logKey(.deviceID, "device=\(deviceID)")

        // ── 5. AppsFlyer ID ──────────────────────────────────────────────
        // Variant A: appsFlyerIDProvider == nil → appsFlyerID = ""
        // Variant B: host provided closure → call it to get UID
        //            AppsFlyerLib.shared().start() has already been called
        //            by the host in performATTForAppsFlyer(), so UID is available
        let appsFlyerID = config.appsFlyerIDProvider?() ?? ""
        if appsFlyerID.isEmpty {
            SRKLogger.log(.debug, "Coordinator: AppsFlyer not connected or UID unavailable")
        } else {
            SRKLogger.log(.info, "Coordinator: appsFlyerID=\(appsFlyerID)")
        }

        // ── 6. POST /register ─────────────────────────────────────────────
        SRKLogger.log(.debug, "Coordinator: step 6 — POST /register")

        let result = await networkManager.fetchRegister(
            fcmToken: fcmToken,
            deviceID: deviceID,
            appsFlyerID: appsFlyerID
        )

        // ── 7. Handle response ───────────────────────────────────────────
        switch result {
        case .success(let response):
            let raw = response.url.trimmingCharacters(in: .whitespacesAndNewlines)
            SRKLogger.log(.info, "Coordinator: register success — url=\(raw)")
            let urlLog = raw.isEmpty ? "(empty — will show main)" : raw
            SRKLogger.logKey(.finalURL, "url=\(urlLog)")

            UserDefaults.standard.set(true,     forKey: sessionDoneKey)
            UserDefaults.standard.set(fcmToken, forKey: sessionFCMKey)
            UserDefaults.standard.set(deviceID, forKey: sessionDeviceKey)

            if isValidWebURL(raw) {
                saveAndApply(.web, url: raw)
            } else {
                SRKLogger.log(.warning, "Coordinator: invalid URL → main")
                saveAndApply(.main, url: nil)
            }

            tryRefreshIfNeeded(currentFCM: fcmToken, deviceID: deviceID)

        case .failure(let error):
            SRKLogger.log(.error, "Coordinator: register error — \(error.localizedDescription)")
            SRKLogger.logKey(.error, "register failed: \(error.localizedDescription)")

            // .noNetwork — no lock saved, next start will retry
            if error == .noNetwork {
                viewModel?.setMain()
                resolved = true
            } else {
                saveAndApply(.main, url: nil)
            }
        }
    }

    // MARK: - Network Check

    private func waitForNetwork(timeoutSeconds: Double = 10.0) async -> Bool {
        SRKLogger.log(.debug, "Coordinator: checking network")

        let monitor = NWPathMonitor()
        let queue   = DispatchQueue(label: "srk.network.check")

        return await withCheckedContinuation { continuation in
            var resumed = false

            monitor.pathUpdateHandler = { path in
                guard !resumed else { return }
                resumed = true
                monitor.cancel()
                let ok = (path.status == .satisfied)
                SRKLogger.log(.debug, "Coordinator: connected=\(ok)")
                continuation.resume(returning: ok)
            }

            monitor.start(queue: queue)

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                guard !resumed else { return }
                resumed = true
                monitor.cancel()
                SRKLogger.log(.warning, "Coordinator: network timeout")
                continuation.resume(returning: false)
            }
        }
    }

    // MARK: - Device ID

    private func resolveDeviceID(attAuthorized: Bool) -> String {
        // Use IDFA if ATT authorized and host stored it in UserDefaults
        if attAuthorized,
           let idfa = UserDefaults.standard.string(forKey: "srk.device.idfa"),
           !idfa.isEmpty,
           idfa != "00000000-0000-0000-0000-000000000000" {
            SRKLogger.log(.debug, "Coordinator: using IDFA")
            return idfa
        }

        // Fallback — stable UUID generated once per install
        if let existing = UserDefaults.standard.string(forKey: stableUUIDKey) {
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: stableUUIDKey)
        SRKLogger.log(.debug, "Coordinator: new stableUUID generated")
        return new
    }

    // MARK: - Helpers

    private func isValidWebURL(_ string: String) -> Bool {
        guard !string.isEmpty,
              let url = URL(string: string),
              let scheme = url.scheme else { return false }
        return scheme == "http" || scheme == "https"
    }

    // MARK: - Route Lock

    private func loadRouteLock() -> SRKRoute? {
        guard let raw = UserDefaults.standard.string(forKey: routeLockKey) else { return nil }
        return SRKRoute(rawValue: raw)
    }

    private func saveAndApply(_ route: SRKRoute, url: String?) {
        UserDefaults.standard.set(route.rawValue, forKey: routeLockKey)
        if let url { UserDefaults.standard.set(url, forKey: storedURLKey) }
        applyRoute(route, url: url)
        resolved = true
    }

    private func applyRoute(_ route: SRKRoute, url: String?) {
        switch route {
        case .main:
            viewModel?.setMain()
        case .web:
            let finalURL = url
                ?? UserDefaults.standard.string(forKey: storedURLKey)
                ?? config.fallbackURL
                ?? config.registerURL
            viewModel?.setWeb(url: finalURL)
        }
    }

    // MARK: - FCM Refresh

    func tryRefreshIfNeeded(currentFCM: String, deviceID: String) {
        guard !currentFCM.isEmpty else { return }

        let sessionDone = UserDefaults.standard.bool(forKey: sessionDoneKey)
        guard sessionDone else { return }

        let attAuthorized = UserDefaults.standard.bool(forKey: attAuthorizedKey)
        guard attAuthorized else {
            SRKLogger.log(.debug, "Sync: skip — ATT not authorized")
            return
        }

        let sessionFCM = UserDefaults.standard.string(forKey: sessionFCMKey) ?? ""
        guard currentFCM != sessionFCM,
              currentFCM != lastRefreshFCM,
              !refreshInFlight else {
            SRKLogger.log(.debug, "Sync: skip")
            return
        }

        refreshInFlight = true
        lastRefreshFCM  = currentFCM
        SRKLogger.log(.info, "Sync: new FCM → POST /sync")
        SRKLogger.logKey(.fcmRefresh, "fcm_refresh=\(String(currentFCM))")

        Task {
            let appsFlyerID = config.appsFlyerIDProvider?() ?? ""
            await networkManager.refresh(
                fcmToken: currentFCM,
                deviceID: deviceID,
                appsFlyerID: appsFlyerID
            )
            await MainActor.run {
                UserDefaults.standard.set(currentFCM, forKey: self.sessionFCMKey)
                self.refreshInFlight = false
            }
        }
    }
}

// MARK: - SRKAPIError Equatable

extension SRKAPIError: Equatable {
    static func == (lhs: SRKAPIError, rhs: SRKAPIError) -> Bool {
        switch (lhs, rhs) {
        case (.noNetwork, .noNetwork),
             (.invalidURL, .invalidURL),
             (.invalidResponse, .invalidResponse),
             (.decodingError, .decodingError):
            return true
        case (.serverError(let a), .serverError(let b)):
            return a == b
        default:
            return false
        }
    }
}
