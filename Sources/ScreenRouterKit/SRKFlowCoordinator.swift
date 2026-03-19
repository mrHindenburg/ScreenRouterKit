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

        if let lock = loadRouteLock() {
            SRKLogger.log(.info, "Coordinator: found lock=\(lock.rawValue)")
            applyRoute(lock, url: UserDefaults.standard.string(forKey: storedURLKey))
            resolved = true
            return
        }

        Task { await runPipeline() }
    }

    // MARK: - Pipeline
    //
    // Flow:
    //   1. Network check
    //   2. ATT — await to completion (needed for correct deviceID)
    //   3. Push permission — triggers APNs/FCM in background
    //   4. Device ID resolved
    //   5. Race: FCM stable token vs splash onComplete() — whichever comes FIRST
    //      unblocks /register. The other task is cancelled.
    //      • FCM wins  → /register fires immediately with the token
    //      • Splash wins → /register fires with cached token or ""
    //      Splash is always ~3s so FCM has that window to arrive.
    //   6. POST /register → open URL
    //   7. Every new FCM token afterward → POST /sync

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

        // ── 2. ATT ───────────────────────────────────────────────────────
        SRKLogger.log(.debug, "Coordinator: step 2 — ATT")
        let attAuthorized = await attGate.requestIfNeeded()
        UserDefaults.standard.set(attAuthorized, forKey: attAuthorizedKey)
        SRKLogger.log(.info, "Coordinator: ATT authorized=\(attAuthorized)")

        // ── 3. Push permission ────────────────────────────────────────────
        if config.pushEnabled {
            await pushGate.requestPermissionOnly()
        }

        // ── 4. Device ID ─────────────────────────────────────────────────
        let deviceID = resolveDeviceID(attAuthorized: attAuthorized)
        SRKLogger.log(.debug, "Coordinator: deviceID=\(deviceID)")
        SRKLogger.logKey(.deviceID, "device=\(deviceID)")

        // ── 5. AppsFlyer ID ──────────────────────────────────────────────
        let appsFlyerID = config.appsFlyerIDProvider?() ?? ""
        if appsFlyerID.isEmpty {
            SRKLogger.log(.debug, "Coordinator: AppsFlyer not connected or UID unavailable")
        } else {
            SRKLogger.log(.info, "Coordinator: appsFlyerID=\(appsFlyerID)")
        }

        // ── 6. Fire /install immediately (no FCM) + wait for splash ─────────
        // /install and splash run in parallel:
        //   • /install fires right away — FCM field is always empty string
        //   • splash plays its animation independently
        // URL from server is held until splash calls onComplete() — only then
        // do we show web or main. This way UX is never blocked by network.
        //
        // FCM is never sent in /install. Stable token → /sync only, after settle.
        SRKLogger.log(.debug, "Coordinator: step 6 — /install + splash in parallel")

        async let installResult = networkManager.fetchRegister(
            fcmToken:    "",
            deviceID:    deviceID,
            appsFlyerID: appsFlyerID
        )
        async let splashWait: Void = waitForSplash()

        let (result, _) = await (installResult, splashWait)

        SRKLogger.log(.debug, "Coordinator: splash done + /install returned — applying route")

        // ── 6b. Background: stable FCM → /sync ───────────────────────────
        Task {
            if let stable = await self.waitForStableFCMTokenBackground() {
                let storedDevice = UserDefaults.standard.string(forKey: self.sessionDeviceKey) ?? ""
                guard !storedDevice.isEmpty else { return }
                SRKLogger.log(.info, "Coordinator: stable FCM ready — triggering /sync")
                await MainActor.run {
                    self.tryRefreshIfNeeded(currentFCM: stable, deviceID: storedDevice)
                }
            }
        }

        // ── 7. Apply route from /install response ─────────────────────────
        SRKLogger.logKey(.fcmFirst, "fcm_at_register=(empty by design)")

        // ── 8. Handle /install response ──────────────────────────────────────
        switch result {
        case .success(let response):
            let raw = response.url.trimmingCharacters(in: .whitespacesAndNewlines)
            SRKLogger.log(.info, "Coordinator: register success — url=\(raw)")
            let urlLog = raw.isEmpty ? "(empty — will show main)" : raw
            SRKLogger.logKey(.finalURL, "url=\(urlLog)")

            UserDefaults.standard.set(true,     forKey: sessionDoneKey)
            UserDefaults.standard.set("",        forKey: sessionFCMKey)   // FCM comes via /sync
            UserDefaults.standard.set(deviceID,  forKey: sessionDeviceKey)

            if isValidWebURL(raw) {
                saveAndApply(.web, url: raw)
            } else {
                SRKLogger.log(.warning, "Coordinator: invalid URL → main")
                saveAndApply(.main, url: nil)
            }

        case .failure(let error):
            SRKLogger.log(.error, "Coordinator: register error — \(error.localizedDescription)")
            SRKLogger.logKey(.error, "register failed: \(error.localizedDescription)")

            if error == .noNetwork {
                viewModel?.setMain()
                resolved = true
            } else {
                saveAndApply(.main, url: nil)
            }
        }
    }

    // MARK: - Splash Wait

    /// Awaits the splash signal fired by SRKRootView when SplashView calls onComplete().
    private func waitForSplash() async {
        SRKLogger.log(.debug, "Coordinator: waiting for splash signal")
        await ScreenRouterKit.shared.splashSignal.wait()
        SRKLogger.log(.debug, "Coordinator: splash signal received")
    }

    // MARK: - Stable FCM Wait (background, no deadline)

    /// Polls until a stable FCM token is observed.
    /// "Stable" = same token unchanged for `stableWindow` seconds.
    /// No timeout — runs until cancelled or stable token found.
    /// Used in background task after /install to feed /sync.
    private func waitForStableFCMTokenBackground(stableWindow: Double = 0.8) async -> String? {
        SRKLogger.log(.debug, "Coordinator: background FCM stability watch started")

        var lastToken:   String? = nil
        var stableSince: Date   = .distantPast

        // Seed from existing storage
        if let t = SRKPushGate.shared.fcmToken
            ?? UserDefaults.standard.string(forKey: "srk.fcm.token"),
           !t.isEmpty {
            lastToken   = t
            stableSince = Date()
        }

        while !Task.isCancelled {
            let current = SRKPushGate.shared.fcmToken
                ?? UserDefaults.standard.string(forKey: "srk.fcm.token")

            if let current, !current.isEmpty {
                if current != lastToken {
                    lastToken   = current
                    stableSince = Date()
                    SRKLogger.log(.debug, "Coordinator: background FCM changed — resetting window")
                } else if Date().timeIntervalSince(stableSince) >= stableWindow {
                    SRKLogger.log(.info, "Coordinator: background FCM stable — \(current)")
                    return current
                }
            }

            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s poll
        }

        return nil
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
        if attAuthorized,
           let idfa = UserDefaults.standard.string(forKey: "srk.device.idfa"),
           !idfa.isEmpty,
           idfa != "00000000-0000-0000-0000-000000000000" {
            SRKLogger.log(.debug, "Coordinator: using IDFA")
            return idfa
        }

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

    /// Sends POST /sync whenever a new FCM token arrives after /register.
    /// ATT check intentionally absent — sync fires regardless of tracking status.
    func tryRefreshIfNeeded(currentFCM: String, deviceID: String) {
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
        SRKLogger.logKey(.fcmRefresh, "fcm_refresh=\(currentFCM)")

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
