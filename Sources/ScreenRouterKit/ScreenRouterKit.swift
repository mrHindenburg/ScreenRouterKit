// ScreenRouterKit.swift
// ScreenRouterKit

import SwiftUI
import Combine

// MARK: - Transition Config

/// Controls how the splash screen disappears.
/// Pass to present() / start() / startWithTracking().
public struct SRKTransitionConfig: Sendable {

    public let animation: Animation
    public let type: SRKTransitionType

    public init(
        type:      SRKTransitionType = .fade,
        animation: Animation         = .easeInOut(duration: 0.6)
    ) {
        self.type      = type
        self.animation = animation
    }

    /// Fade out — default
    public static let fade = SRKTransitionConfig(type: .fade, animation: .easeInOut(duration: 0.6))

    /// Slide splash upward
    public static let slideUp = SRKTransitionConfig(type: .slide(.up), animation: .easeInOut(duration: 0.5))

    /// Slide splash downward
    public static let slideDown = SRKTransitionConfig(type: .slide(.down), animation: .easeInOut(duration: 0.5))

    /// Scale + fade
    public static let scale = SRKTransitionConfig(type: .scale, animation: .easeInOut(duration: 0.5))

    /// Custom — provide your own type and animation
    public static func custom(type: SRKTransitionType, animation: Animation) -> SRKTransitionConfig {
        SRKTransitionConfig(type: type, animation: animation)
    }
}

public enum SRKTransitionType: Sendable {
    case fade
    case slide(Edge)
    case scale

    public enum Edge: Sendable {
        case up, down, left, right
    }
}

// MARK: - ScreenRouterKit Facade

@MainActor
public final class ScreenRouterKit {

    // MARK: Singleton

    public static let shared = ScreenRouterKit()
    private init() {}

    // MARK: Internal State

    private(set) var config: SRKConfiguration?
    private(set) var transitionConfig: SRKTransitionConfig = .fade
    private(set) var mainViewProvider: SRKMainViewProvider?
    private var viewModel: SRKViewModel?
    private var started = false

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: SIMPLE — splash only, no networking
    // MARK: ─────────────────────────────────────────────────────────────────

    /// Simple entry point — no API, no ATT, no push.
    /// Library shows splash, waits for onComplete() callback, then fades to mainView.
    ///
    /// ```swift
    /// WindowGroup {
    ///     ScreenRouterKit.shared.present(
    ///         splash:   { onComplete in AnyView(SplashView(onComplete: onComplete)) },
    ///         mainView: { AnyView(ContentView()) }
    ///     )
    /// }
    /// ```
    public func present(
        transition: SRKTransitionConfig = .fade,
        splash: @escaping SRKSplashProviderSimple,
        mainView: @escaping SRKMainViewProvider,
        debugMode: SRKDebugMode = .disabled,
        attHandling: SRKATTHandling = .managedByLibrary,
        defaultOrientations: UIInterfaceOrientationMask = .portrait,
        webOrientations: UIInterfaceOrientationMask = .all
    ) -> some View {

        mainViewProvider    = mainView
        transitionConfig    = transition

        let config = SRKConfiguration(
            splash:              splash,
            debugMode:           debugMode,
            attHandling:         attHandling,
            defaultOrientations: defaultOrientations,
            webOrientations:     webOrientations
        )

        configure(config)

        // In simple mode pipeline just sets .main immediately —
        // actual dismissal is driven by onComplete() from SplashView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.startSimple()
        }

        return makeRootView()
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: VARIANT A — without AppsFlyer
    // MARK: ─────────────────────────────────────────────────────────────────

    /// Single entry point for variant A.
    /// Returns a self-contained View that switches between splash / WebView / mainView.
    ///
    /// ```swift
    /// WindowGroup {
    ///     ScreenRouterKit.shared.start(
    ///         registerURL: "https://your-domain.com/v1/public/register",
    ///         syncURL: "https://your-domain.com/v1/public/sync",
    ///         bundleID:   "6759095589",
    ///         splash:     { AnyView(SplashView()) },
    ///         mainView:   { AnyView(ContentView()) }
    ///     )
    /// }
    /// ```
    public func start(
        registerURL: String,
        syncURL: String,
        bundleID: String,
        splash: SRKSplashProvider?,
        mainView: SRKMainViewProvider?,
        debugMode: SRKDebugMode = .disabled,
        pushEnabled: Bool = true,
        fallbackURL: String? = nil,
        defaultOrientations: UIInterfaceOrientationMask = .portrait,
        webOrientations: UIInterfaceOrientationMask = .all
    ) -> some View {

        mainViewProvider = mainView

        let config = SRKConfiguration(
            registerURL: registerURL,
            syncURL: syncURL,
            bundleID: bundleID,
            attHandling: .managedByLibrary,
            splash: splash,
            debugMode: debugMode,
            pushEnabled: pushEnabled,
            fallbackURL: fallbackURL,
            defaultOrientations: defaultOrientations,
            webOrientations: webOrientations
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
    /// Identical interface to start() — host sees no difference.
    ///
    /// ```swift
    /// WindowGroup {
    ///     ScreenRouterKit.shared.startWithTracking(
    ///         registerURL: "https://your-domain.com/v1/public/register",
    ///         syncURL: "https://your-domain.com/v1/public/sync",
    ///         bundleID:   "6759095589",
    ///         splash:     { AnyView(SplashView()) },
    ///         mainView:   { AnyView(ContentView()) }
    ///     )
    /// }
    /// ```
    public func startWithTracking(
        registerURL: String,
        syncURL: String,
        bundleID: String,
        splash: SRKSplashProvider?,
        mainView: SRKMainViewProvider?,
        debugMode: SRKDebugMode = .disabled,
        pushEnabled: Bool = true,
        fallbackURL: String? = nil,
        defaultOrientations: UIInterfaceOrientationMask = .portrait,
        webOrientations: UIInterfaceOrientationMask = .all
    ) -> some View {

        mainViewProvider = mainView

        let signal = SRKATTSignal()

        if let delegate = UIApplication.shared.delegate as? SRKAppDelegate {
            delegate.attSignal        = signal
            delegate.appsFlyerEnabled = true
        } else {
            SRKLogger.log(.warning, "startWithTracking: AppDelegate is not SRKAppDelegate")
        }

        let config = SRKConfiguration(
            registerURL:          registerURL,
            syncURL:          syncURL,
            bundleID:            bundleID,
            attSignal:           signal,
            appsFlyerIDProvider: {
                UserDefaults.standard.string(forKey: "srk.appsflyer.id")
            },
            splash:              splash,
            debugMode:           debugMode,
            pushEnabled:         pushEnabled,
            fallbackURL:         fallbackURL,
            defaultOrientations: defaultOrientations,
            webOrientations:     webOrientations
        )

        configure(config)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.start()

            if let delegate = UIApplication.shared.delegate as? SRKAppDelegate {
                delegate.performATTForAppsFlyer()
            }
        }

        return makeRootView()
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: Core API
    // MARK: ─────────────────────────────────────────────────────────────────

    public func configure(_ config: SRKConfiguration) {
        self.config = config
        SRKLogger.mode = config.debugMode
        SRKLogger.log(.info, "ScreenRouterKit: configure() bundleID=\(config.bundleID)")
    }

    public func makeRootView() -> some View {
        let vm = getOrCreateViewModel()
        return SRKRootView().environmentObject(vm)
    }

    public func start() {
        guard let config else {
            SRKLogger.log(.error, "ScreenRouterKit: start() called before configure()")
            return
        }
        guard !started else {
            SRKLogger.log(.debug, "ScreenRouterKit: start() already called")
            return
        }
        started = true
        SRKLogger.log(.info, "ScreenRouterKit: start()")

        guard let vm = viewModel else {
            SRKLogger.log(.error, "ScreenRouterKit: ViewModel not found")
            return
        }
        vm.begin(config: config)
    }


    func startSimple() {
            guard let config, !started else { return }
            started = true
            SRKLogger.mode = config.debugMode
            SRKLogger.log(.info, "ScreenRouterKit: startSimple()")

            Task { @MainActor in
                // Run ATT if configured — skip does nothing
                let attGate = SRKATTGate(handling: config.attHandling)
                let attAuthorized = await attGate.requestIfNeeded()
                UserDefaults.standard.set(attAuthorized, forKey: "srk.att.authorized")
                SRKLogger.log(.info, "ScreenRouterKit: startSimple — ATT authorized=\(attAuthorized)")

                // Splash will fade out when SplashView calls onComplete()
                viewModel?.setMain()
            }
        }

    // MARK: - Token Handlers

    public func handleAPNSToken(_ data: Data) {
        let hex = data.map { String(format: "%02.2hhx", $0) }.joined()
        SRKLogger.log(.info, "ScreenRouterKit: APNs (\(hex)")
        UserDefaults.standard.set(true, forKey: "srkApnsReady")
        UserDefaults.standard.set(hex,  forKey: "srkApnsTokenHex")
        SRKPushGate.shared.srk_apnsToken = hex
        NotificationCenter.default.post(name: .srkAPNSTokenDidUpdate, object: nil,
                                        userInfo: ["srk_apns": hex])
    }

    public func handleFCMToken(_ token: String) {
        guard !token.isEmpty else { return }

        let isRefresh = started  // token arrived after pipeline already ran → refresh

        if isRefresh {
            SRKLogger.logKey(.fcmRefresh, "fcm_refresh=\(token)")
        } else {
            SRKLogger.logKey(.fcmFirst, "fcm_early=\(token)")
        }

        UserDefaults.standard.set(token, forKey: "srk.fcm.token")
        SRKPushGate.shared.fcmToken = token
        NotificationCenter.default.post(name: .srkFCMTokenDidUpdate, object: nil,
                                        userInfo: ["token": token])
    }

    // MARK: - Orientation

    public var currentOrientations: UIInterfaceOrientationMask {
        config?.defaultOrientations ?? .portrait
    }

    // MARK: - State

    public var presented: SRKScene {
        viewModel?.presented ?? .loading
    }

    public var presentedPublisher: Published<SRKScene>.Publisher? {
        viewModel?.$presented
    }

    // MARK: - Reset

    public func reset() {
        SRKLogger.log(.info, "ScreenRouterKit: reset()")
        [
            "srk.flow.lock", "srk.flow.url",
            "srk.session.done", "srk.session.fcm", "srk.session.device",
            "srk.att.authorized", "srk.stable.uuid",
            "srk.device.idfa", "srk.appsflyer.id"
        ].forEach { UserDefaults.standard.removeObject(forKey: $0) }
        started          = false
        viewModel        = nil
        mainViewProvider = nil
    }

    // MARK: - Private

    private func getOrCreateViewModel() -> SRKViewModel {
        if let existing = viewModel { return existing }
        let vm = SRKViewModel()
        viewModel = vm
        return vm
    }
}
