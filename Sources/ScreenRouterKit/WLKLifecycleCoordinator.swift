// WLKLifecycleCoordinator.swift
// ScreenRouterKit

import Foundation
import Network

// MARK: - Route Lock

enum WLKRoute: String {
    case main
    case web
}

// MARK: - Coordinator

@MainActor
final class WLKLifecycleCoordinator {

    // MARK: Dependencies

    private let config: WLKConfiguration
    private let attGate: WLKATTGate
    private let pushGate: WLKPushGate
    private let networkManager: WLKNetworkManager

    // MARK: State

    weak var viewModel: WLKViewModel?

    private var resolved        = false
    private var refreshInFlight = false
    private var lastRefreshFCM: String?

    // MARK: UserDefaults Keys

    private let routeLockKey     = "wlk.route.lock"
    private let storedURLKey     = "wlk.route.url"
    private let installDoneKey   = "wlk.install.done"
    private let installFCMKey    = "wlk.install.fcm"
    private let installDeviceKey = "wlk.install.device"
    private let attAuthorizedKey = "wlk.att.authorized"
    private let stableUUIDKey    = "wlk.stable.uuid"

    // MARK: Init

    init(config: WLKConfiguration) {
        self.config         = config
        self.attGate        = WLKATTGate(handling: config.attHandling)
        self.pushGate       = WLKPushGate(enabled: config.pushEnabled)
        self.networkManager = WLKNetworkManager(config: config)
    }

    // MARK: - Start

    func start() {
        guard !resolved else {
            WLKLogger.log(.debug, "Coordinator: already resolved — start() ignored")
            return
        }

        WLKLogger.log(.debug, "Coordinator: start()")

        // Subsequent launch — read saved lock, skip API call
        if let lock = loadRouteLock() {
            WLKLogger.log(.info, "Coordinator: found lock=\(lock.rawValue)")
            applyRoute(lock, url: UserDefaults.standard.string(forKey: storedURLKey))
            resolved = true
            return
        }

        Task { await runPipeline() }
    }

    // MARK: - Pipeline

    private func runPipeline() async {
        WLKLogger.log(.debug, "Coordinator: pipeline start")
        viewModel?.setLoading()

        // ── 1. Network ───────────────────────────────────────────────────
        guard await waitForNetwork() else {
            WLKLogger.log(.info, "Coordinator: no network → main (no lock)")
            viewModel?.setMain()
            resolved = true
            return
        }

        // ── 2. ATT ────────────────────────────────────────────────────────
        // Variant A: library shows the ATT alert itself
        // Variant B: library waits for signal.complete() from host
        //            (host calls AppsFlyerLib.shared().start() between ATT and this point)
        WLKLogger.log(.debug, "Coordinator: step 2 — ATT")
        let attAuthorized = await attGate.requestIfNeeded()
        UserDefaults.standard.set(attAuthorized, forKey: attAuthorizedKey)
        WLKLogger.log(.info, "Coordinator: ATT authorized=\(attAuthorized)")

        // ── 3. Push + FCM ────────────────────────────────────────────────
        WLKLogger.log(.debug, "Coordinator: step 3 — Push + FCM")
        let fcmToken = await pushGate.requestAndCollect() ?? ""
        let fcmLog = fcmToken.isEmpty ? "(empty)" : fcmToken
        WLKLogger.logKey(.fcmFirst, "fcm=\(fcmLog)")

        // ── 4. Device ID ─────────────────────────────────────────────────
        let deviceID = resolveDeviceID(attAuthorized: attAuthorized)
        WLKLogger.log(.debug, "Coordinator: deviceID=\(deviceID)")
        WLKLogger.logKey(.deviceID, "device=\(deviceID)")

        // ── 5. AppsFlyer ID ──────────────────────────────────────────────
        // Variant A: appsFlyerIDProvider == nil → appsFlyerID = ""
        // Variant B: host provided closure → call it to get UID
        //            AppsFlyerLib.shared().start() has already been called
        //            by the host in performATTForAppsFlyer(), so UID is available
        let appsFlyerID = config.appsFlyerIDProvider?() ?? ""
        if appsFlyerID.isEmpty {
            WLKLogger.log(.debug, "Coordinator: AppsFlyer not connected or UID unavailable")
        } else {
            WLKLogger.log(.info, "Coordinator: appsFlyerID=\(appsFlyerID)")
        }

        // ── 6. POST /install ─────────────────────────────────────────────
        WLKLogger.log(.debug, "Coordinator: step 6 — POST /install")

        let result = await networkManager.fetchInstall(
            fcmToken: fcmToken,
            deviceID: deviceID,
            appsFlyerID: appsFlyerID
        )

        // ── 7. Handle response ───────────────────────────────────────────
        switch result {
        case .success(let response):
            let raw = response.url.trimmingCharacters(in: .whitespacesAndNewlines)
            WLKLogger.log(.info, "Coordinator: install success — url=\(raw)")
            let urlLog = raw.isEmpty ? "(empty — will show main)" : raw
            WLKLogger.logKey(.finalURL, "url=\(urlLog)")

            UserDefaults.standard.set(true,     forKey: installDoneKey)
            UserDefaults.standard.set(fcmToken, forKey: installFCMKey)
            UserDefaults.standard.set(deviceID, forKey: installDeviceKey)

            if isValidWebURL(raw) {
                saveAndApply(.web, url: raw)
            } else {
                WLKLogger.log(.warning, "Coordinator: invalid URL → main")
                saveAndApply(.main, url: nil)
            }

            tryRefreshIfNeeded(currentFCM: fcmToken, deviceID: deviceID)

        case .failure(let error):
            WLKLogger.log(.error, "Coordinator: install error — \(error.localizedDescription)")
            WLKLogger.logKey(.error, "install failed: \(error.localizedDescription)")

            // .noNetwork — no lock saved, next launch will retry
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
        WLKLogger.log(.debug, "Coordinator: checking network")

        let monitor = NWPathMonitor()
        let queue   = DispatchQueue(label: "wlk.network.check")

        return await withCheckedContinuation { continuation in
            var resumed = false

            monitor.pathUpdateHandler = { path in
                guard !resumed else { return }
                resumed = true
                monitor.cancel()
                let ok = (path.status == .satisfied)
                WLKLogger.log(.debug, "Coordinator: connected=\(ok)")
                continuation.resume(returning: ok)
            }

            monitor.start(queue: queue)

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                guard !resumed else { return }
                resumed = true
                monitor.cancel()
                WLKLogger.log(.warning, "Coordinator: network timeout")
                continuation.resume(returning: false)
            }
        }
    }

    // MARK: - Device ID

    private func resolveDeviceID(attAuthorized: Bool) -> String {
        // Use IDFA if ATT authorized and host stored it in UserDefaults
        if attAuthorized,
           let idfa = UserDefaults.standard.string(forKey: "wlk.device.idfa"),
           !idfa.isEmpty,
           idfa != "00000000-0000-0000-0000-000000000000" {
            WLKLogger.log(.debug, "Coordinator: using IDFA")
            return idfa
        }

        // Fallback — stable UUID generated once per install
        if let existing = UserDefaults.standard.string(forKey: stableUUIDKey) {
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: stableUUIDKey)
        WLKLogger.log(.debug, "Coordinator: new stableUUID generated")
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

    private func loadRouteLock() -> WLKRoute? {
        guard let raw = UserDefaults.standard.string(forKey: routeLockKey) else { return nil }
        return WLKRoute(rawValue: raw)
    }

    private func saveAndApply(_ route: WLKRoute, url: String?) {
        UserDefaults.standard.set(route.rawValue, forKey: routeLockKey)
        if let url { UserDefaults.standard.set(url, forKey: storedURLKey) }
        applyRoute(route, url: url)
        resolved = true
    }

    private func applyRoute(_ route: WLKRoute, url: String?) {
        switch route {
        case .main:
            viewModel?.setMain()
        case .web:
            let finalURL = url
                ?? UserDefaults.standard.string(forKey: storedURLKey)
                ?? config.fallbackURL
                ?? config.installURL
            viewModel?.setWeb(url: finalURL)
        }
    }

    // MARK: - FCM Refresh

    func tryRefreshIfNeeded(currentFCM: String, deviceID: String) {
        guard !currentFCM.isEmpty else { return }

        let installDone = UserDefaults.standard.bool(forKey: installDoneKey)
        guard installDone else { return }

        let attAuthorized = UserDefaults.standard.bool(forKey: attAuthorizedKey)
        guard attAuthorized else {
            WLKLogger.log(.debug, "Refresh: skip — ATT not authorized")
            return
        }

        let installFCM = UserDefaults.standard.string(forKey: installFCMKey) ?? ""
        guard currentFCM != installFCM,
              currentFCM != lastRefreshFCM,
              !refreshInFlight else {
            WLKLogger.log(.debug, "Refresh: skip")
            return
        }

        refreshInFlight = true
        lastRefreshFCM  = currentFCM
        WLKLogger.log(.info, "Refresh: new FCM → POST /refresh")
        WLKLogger.logKey(.fcmRefresh, "fcm_refresh=\(currentFCM)")

        Task {
            let appsFlyerID = config.appsFlyerIDProvider?() ?? ""
            await networkManager.refresh(
                fcmToken: currentFCM,
                deviceID: deviceID,
                appsFlyerID: appsFlyerID
            )
            await MainActor.run {
                UserDefaults.standard.set(currentFCM, forKey: self.installFCMKey)
                self.refreshInFlight = false
            }
        }
    }
}

// MARK: - WLKAPIError Equatable

extension WLKAPIError: Equatable {
    static func == (lhs: WLKAPIError, rhs: WLKAPIError) -> Bool {
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
