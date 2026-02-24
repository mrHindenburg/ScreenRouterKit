// ScreenRouterKit.swift
// ScreenRouterKit

import SwiftUI
import Combine

// MARK: - View Provider

public typealias WLKMainViewProvider = () -> AnyView

// MARK: - WebLoaderKit Facade

@MainActor
public final class ScreenRouterKit {

    // MARK: Singleton

    public static let shared = ScreenRouterKit()
    private init() {}

    // MARK: Internal State

    private(set) var config: WLKConfiguration?
    private(set) var mainViewProvider: WLKMainViewProvider?
    private var viewModel: WLKViewModel?
    private var started = false

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: VARIANT A — without AppsFlyer
    // MARK: ─────────────────────────────────────────────────────────────────

    /// Single entry point for variant A.
    /// Returns a self-contained View that switches between splash / WebView / mainView.
    ///
    /// ```swift
    /// WindowGroup {
    ///     ScreenRouterKit.shared.launch(
    ///         installURL: "https://your-domain.com/v1/public/install",
    ///         refreshURL: "https://your-domain.com/v1/public/refresh",
    ///         bundleID:   "6759095589",
    ///         splash:     { AnyView(SplashView()) },
    ///         mainView:   { AnyView(ContentView()) }
    ///     )
    /// }
    /// ```
    public func launch(
        installURL: String,
        refreshURL: String,
        bundleID: String,
        splash: WLKSplashProvider? = nil,
        mainView: WLKMainViewProvider? = nil,
        debugMode: WLKDebugMode = .disabled,
        pushEnabled: Bool = true,
        fallbackURL: String? = nil,
        defaultOrientations: UIInterfaceOrientationMask = .portrait,
        webOrientations: UIInterfaceOrientationMask = .all
    ) -> some View {

        mainViewProvider = mainView

        let config = WLKConfiguration(
            installURL:          installURL,
            refreshURL:          refreshURL,
            bundleID:            bundleID,
            attHandling:         .managedByLibrary,
            splashProvider:      splash,
            debugMode:           debugMode,
            pushEnabled:         pushEnabled,
            fallbackURL:         fallbackURL,
            defaultOrientations: defaultOrientations,
            webOrientations:     webOrientations
        )

        configure(config)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.start()
        }

        return makeRootView()
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: VARIANT B — with AppsFlyer
    // MARK: ─────────────────────────────────────────────────────────────────

    /// Single entry point for variant B.
    /// Identical interface to launch() — host sees no difference.
    ///
    /// ```swift
    /// WindowGroup {
    ///     ScreenRouterKit.shared.launchWithAppsFlyer(
    ///         installURL: "https://your-domain.com/v1/public/install",
    ///         refreshURL: "https://your-domain.com/v1/public/refresh",
    ///         bundleID:   "6759095589",
    ///         splash:     { AnyView(SplashView()) },
    ///         mainView:   { AnyView(ContentView()) }
    ///     )
    /// }
    /// ```
    public func launchWithAppsFlyer(
        installURL: String,
        refreshURL: String,
        bundleID: String,
        splash: WLKSplashProvider? = nil,
        mainView: WLKMainViewProvider? = nil,
        debugMode: WLKDebugMode = .disabled,
        pushEnabled: Bool = true,
        fallbackURL: String? = nil,
        defaultOrientations: UIInterfaceOrientationMask = .portrait,
        webOrientations: UIInterfaceOrientationMask = .all
    ) -> some View {

        mainViewProvider = mainView

        let signal = WLKATTSignal()

        if let delegate = UIApplication.shared.delegate as? WLKAppDelegate {
            delegate.attSignal        = signal
            delegate.appsFlyerEnabled = true
        } else {
            WLKLogger.log(.warning, "launchWithAppsFlyer: AppDelegate is not WLKAppDelegate")
        }

        let config = WLKConfiguration(
            installURL:          installURL,
            refreshURL:          refreshURL,
            bundleID:            bundleID,
            attSignal:           signal,
            appsFlyerIDProvider: {
                UserDefaults.standard.string(forKey: "wlk.appsflyer.id")
            },
            splashProvider:      splash,
            debugMode:           debugMode,
            pushEnabled:         pushEnabled,
            fallbackURL:         fallbackURL,
            defaultOrientations: defaultOrientations,
            webOrientations:     webOrientations
        )

        configure(config)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.start()

            if let delegate = UIApplication.shared.delegate as? WLKAppDelegate {
                delegate.performATTForAppsFlyer()
            }
        }

        return makeRootView()
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: Core API
    // MARK: ─────────────────────────────────────────────────────────────────

    public func configure(_ config: WLKConfiguration) {
        self.config = config
        WLKLogger.mode = config.debugMode
        WLKLogger.log(.info, "WebLoaderKit: configure() bundleID=\(config.bundleID)")
    }

    public func makeRootView() -> some View {
        let vm = getOrCreateViewModel()
        return WLKRootView().environmentObject(vm)
    }

    public func start() {
        guard let config else {
            WLKLogger.log(.error, "WebLoaderKit: start() called before configure()")
            return
        }
        guard !started else {
            WLKLogger.log(.debug, "WebLoaderKit: start() already called")
            return
        }
        started = true
        WLKLogger.log(.info, "WebLoaderKit: start()")

        guard let vm = viewModel else {
            WLKLogger.log(.error, "WebLoaderKit: ViewModel not found")
            return
        }
        vm.begin(config: config)
    }

    // MARK: - Token Handlers

    public func handleAPNSToken(_ data: Data) {
        let hex = data.map { String(format: "%02.2hhx", $0) }.joined()
        WLKLogger.log(.info, "WebLoaderKit: APNs (\(hex))")
        UserDefaults.standard.set(true, forKey: "apnsReady")
        UserDefaults.standard.set(hex,  forKey: "apnsTokenHex")
        WLKPushGate.shared.apnsToken = hex
        NotificationCenter.default.post(name: .wlkAPNSTokenDidUpdate, object: nil,
                                        userInfo: ["apns": hex])
    }

    public func handleFCMToken(_ token: String) {
        guard !token.isEmpty else { return }

        let isRefresh = started  // token arrived after pipeline already ran → refresh

        if isRefresh {
            WLKLogger.logKey(.fcmRefresh, "fcm_refresh=\(token)")
        } else {
            WLKLogger.logKey(.fcmFirst, "fcm_early=\(token)")
        }

        UserDefaults.standard.set(token, forKey: "fcmToken")
        WLKPushGate.shared.fcmToken = token
        NotificationCenter.default.post(name: .wlkFCMTokenDidUpdate, object: nil,
                                        userInfo: ["token": token])
    }

    // MARK: - Orientation

    public var currentOrientations: UIInterfaceOrientationMask {
        config?.defaultOrientations ?? .portrait
    }

    // MARK: - State

    public var presented: WLKPresented {
        viewModel?.presented ?? .loading
    }

    public var presentedPublisher: Published<WLKPresented>.Publisher? {
        viewModel?.$presented
    }

    // MARK: - Reset

    public func reset() {
        WLKLogger.log(.info, "WebLoaderKit: reset()")
        [
            "wlk.route.lock", "wlk.route.url",
            "wlk.install.done", "wlk.install.fcm", "wlk.install.device",
            "wlk.att.authorized", "wlk.stable.uuid",
            "wlk.device.idfa", "wlk.appsflyer.id"
        ].forEach { UserDefaults.standard.removeObject(forKey: $0) }
        started          = false
        viewModel        = nil
        mainViewProvider = nil
    }

    // MARK: - Private

    private func getOrCreateViewModel() -> WLKViewModel {
        if let existing = viewModel { return existing }
        let vm = WLKViewModel()
        viewModel = vm
        return vm
    }
}
