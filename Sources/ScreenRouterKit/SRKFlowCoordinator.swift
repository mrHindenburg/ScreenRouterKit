import Foundation
import Network
import AdSupport

enum SRKRoute: String {
    case main
    case web
}

@MainActor
final class SRKFlowCoordinator {

    private let config: SRKConfiguration
    private let attGate: SRKATTGate
    private let pushGate: SRKPushGate
    private let networkManager: SRKNetworkManager

    weak var viewModel: SRKRouterViewModel?

    private var resolved        = false
    private var refreshInFlight = false
    private var lastRefreshFCM: String?

    private let routeLockKey     = "wbc.flow.lock"
    private let storedURLKey     = "wbc.flow.url"
    private let sessionDoneKey   = "wbc.session.done"
    private let sessionFCMKey    = "wbc.session.fcm"
    private let sessionDeviceKey = "wbc.session.device"
    private let attAuthorizedKey = "wbc.att.authorized"
    private let stableUUIDKey    = "wbc.stable.uuid"

    init(config: SRKConfiguration) {
        self.config         = config
        self.attGate        = SRKATTGate(handling: config.attHandling, delay: config.attDelay)
        self.pushGate       = SRKPushGate(enabled: config.pushEnabled)
        self.networkManager = SRKNetworkManager(config: config)
    }

    func start() {
        guard !resolved else {
            SRKLogger.log(.debug, "Coordinator: already resolved — start() ignored")
            return
        }

        SRKLogger.log(.debug, "Coordinator: start()")

        if let lock = loadRouteLock() {
            SRKLogger.log(.info, "Coordinator: found lock=\(lock.rawValue)")
            applyRoute(lock, url: UserDefaults.standard.string(forKey: storedURLKey))
            resolved = true
            return
        }

        Task { await runPipeline() }
    }

    private func runPipeline() async {
        SRKLogger.log(.debug, "Coordinator: pipeline start")
        viewModel?.setLoading()

        guard await waitForNetwork() else {
            SRKLogger.log(.info, "Coordinator: no network → main (no lock)")
            viewModel?.setMain()
            resolved = true
            return
        }

        SRKLogger.log(.debug, "Coordinator: step 2 — ATT")
        let attAuthorized = await attGate.requestIfNeeded()
        UserDefaults.standard.set(attAuthorized, forKey: attAuthorizedKey)
        SRKLogger.log(.info, "Coordinator: ATT authorized=\(attAuthorized)")

        if config.pushEnabled {
            // wait for ATT system dialog to fully dismiss before showing push prompt
            try? await Task.sleep(nanoseconds: 600_000_000)
            await pushGate.requestPermissionOnly()
        }

        let deviceID = resolveDeviceID(attAuthorized: attAuthorized)
        SRKLogger.log(.debug, "Coordinator: deviceID=\(deviceID ?? "—")")
        startFCMTokenObserver(deviceID: deviceID)

        if config.appsFlyerSignal != nil {
            SRKLogger.af(.debug, "Coordinator: step 5 — waiting for AppsFlyer conversion data")
            await waitForAppsFlyerConversionData()
        }

        let appsFlyerID = config.appsFlyerIDProvider?() ?? ""
        if appsFlyerID.isEmpty {
            SRKLogger.af(.debug, "Coordinator: AppsFlyer not connected or UID unavailable")
        } else {
            SRKLogger.af(.info, "Coordinator: appsFlyerID=\(appsFlyerID)")
        }

        SRKLogger.log(.debug, "Coordinator: step 6 — /install + splash in parallel")

        async let installResult = networkManager.fetchRegister(
            fcmToken:    "",
            deviceID:    deviceID,
            appsFlyerID: appsFlyerID
        )
        async let splashWait: Void = waitForSplash()

        let (result, _) = await (installResult, splashWait)

        SRKLogger.log(.debug, "Coordinator: splash done + /install returned — applying route")

        switch result {
        case .success(let response):
            let raw = response.url.trimmingCharacters(in: .whitespacesAndNewlines)
            SRKLogger.log(.info, "Coordinator: register success — url=\(raw)")

            UserDefaults.standard.set(true,           forKey: sessionDoneKey)
            UserDefaults.standard.set("",             forKey: sessionFCMKey)
            UserDefaults.standard.set(deviceID ?? "", forKey: sessionDeviceKey)

            if isValidWebURL(raw) {
                saveAndApply(.web, url: raw)
            } else {
                SRKLogger.log(.warning, "Coordinator: invalid URL → main")
                saveAndApply(.main, url: nil)
            }

        case .failure(let error):
            SRKLogger.log(.error, "Coordinator: register error — \(error.localizedDescription)")

            if error == .noNetwork {
                viewModel?.setMain()
                resolved = true
            } else {
                saveAndApply(.main, url: nil)
            }
        }
    }

    private func waitForSplash() async {
        SRKLogger.log(.debug, "Coordinator: waiting for splash signal")
        await ScreenRouterKit.shared.splashSignal.wait()
        SRKLogger.log(.debug, "Coordinator: splash signal received")
    }

    private func waitForAppsFlyerConversionData(timeoutSeconds: Double = 60.0) async {
        guard let signal = config.appsFlyerSignal else { return }

        let signalReceived = await withTaskGroup(of: Bool.self) { group -> Bool in
            group.addTask {
                await signal.wait()
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        if signalReceived {
            SRKLogger.af(.info, "Coordinator: AppsFlyer conversion data received → proceeding to /install")
        } else {
            SRKLogger.af(.warning, "Coordinator: AppsFlyer wait timeout (\(timeoutSeconds)s) → /install will go without appsInfo")
        }
    }

    private func startFCMTokenObserver(deviceID: String?) {
        Task {
            SRKLogger.log(.debug, "Coordinator: Background FCM observer started")
            
            while !Task.isCancelled {
                let currentFCM = SRKPushGate.shared.fcmToken ?? UserDefaults.standard.string(forKey: "wbc.fcm.token") ?? ""
                
                let sessionDone = UserDefaults.standard.bool(forKey: sessionDoneKey)

                if sessionDone, !currentFCM.isEmpty, currentFCM != self.lastRefreshFCM, !self.refreshInFlight {
                    SRKLogger.log(.info, "Coordinator: New stable FCM detected — triggering /sync")
                    await MainActor.run {
                        self.tryRefreshIfNeeded(currentFCM: currentFCM, deviceID: deviceID)
                    }
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func waitForNetwork(timeoutSeconds: Double = 10.0) async -> Bool {
        SRKLogger.log(.debug, "Coordinator: checking network")

        let monitor = NWPathMonitor()
        let queue   = DispatchQueue(label: "wbc.network.check")

        let stream = AsyncStream(Bool.self) { cont in
            monitor.pathUpdateHandler = { path in
                cont.yield(path.status == .satisfied)
                cont.finish()
            }
            cont.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: queue)
        }

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await connected in stream { return connected }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                guard !Task.isCancelled else { return false }
                SRKLogger.log(.warning, "Coordinator: network timeout")
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            SRKLogger.log(.debug, "Coordinator: connected=\(result)")
            return result
        }
    }

    private func resolveDeviceID(attAuthorized: Bool) -> String? {
        if attAuthorized {
            // Read IDFA directly: the UserDefaults key is only populated in the
            // AppsFlyer scenario (performATTForAppsFlyer), so .managedByLibrary
            // flows would otherwise never send a device ID.
            let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
            if idfa != "00000000-0000-0000-0000-000000000000" {
                UserDefaults.standard.set(idfa, forKey: "wbc.device.idfa")
                SRKLogger.key("device = IDFA → \(idfa)")
                return idfa
            }

            if let cached = UserDefaults.standard.string(forKey: "wbc.device.idfa"),
               !cached.isEmpty,
               cached != "00000000-0000-0000-0000-000000000000" {
                SRKLogger.key("device = cached IDFA → \(cached)")
                return cached
            }
        }

        // No IDFA (ATT denied or zeroed) — fall back to a stable per-install
        // UUID so the server can always match install ↔ refresh by device.
        if let existing = UserDefaults.standard.string(forKey: stableUUIDKey),
           !existing.isEmpty {
            SRKLogger.key("device = stable UUID (no IDFA) → \(existing)")
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: stableUUIDKey)
        SRKLogger.key("device = stable UUID generated (no IDFA) → \(new)")
        return new
    }

    private func isValidWebURL(_ string: String) -> Bool {
        guard !string.isEmpty,
              let url = URL(string: string),
              let scheme = url.scheme else { return false }
        return scheme == "http" || scheme == "https"
    }

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
            guard !config.nativeOnly else {
                SRKLogger.log(.info, "Coordinator: nativeOnly=true — suppressing WebView, showing main")
                viewModel?.setMain()
                return
            }
            let finalURL = url
                ?? UserDefaults.standard.string(forKey: storedURLKey)
                ?? config.fallbackURL
                ?? config.registerURL
            viewModel?.setWeb(url: finalURL)
        }
    }

    func tryRefreshIfNeeded(currentFCM: String, deviceID: String?) {
        guard !currentFCM.isEmpty else { return }

        let sessionDone = UserDefaults.standard.bool(forKey: sessionDoneKey)
        guard sessionDone else {
            SRKLogger.log(.debug, "Sync: skip — session not done")
            return
        }

        let sessionFCM = UserDefaults.standard.string(forKey: sessionFCMKey) ?? ""
        guard currentFCM != sessionFCM,
              currentFCM != lastRefreshFCM,
              !refreshInFlight else {
            SRKLogger.log(.debug, "Sync: skip — token unchanged or in flight")
            return
        }

        refreshInFlight = true
        lastRefreshFCM  = currentFCM
        SRKLogger.log(.info, "Sync: new FCM → POST /sync")

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

extension SRKAPIError: Equatable {
    static func == (lhs: SRKAPIError, rhs: SRKAPIError) -> Bool {
        switch (lhs, rhs) {
        case (.noNetwork, .noNetwork),
             (.invalidURL, .invalidURL),
             (.invalidResponse, .invalidResponse),
             (.decodingError, .decodingError):
            return true
        case (.serverError(let a, _), .serverError(let b, _)):
            return a == b
        default:
            return false
        }
    }
}
