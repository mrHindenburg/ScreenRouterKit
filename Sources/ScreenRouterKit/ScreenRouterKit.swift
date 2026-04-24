import SwiftUI
import Combine

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

    public static let fade      = SRKTransitionConfig(type: .fade,           animation: .easeInOut(duration: 0.6))
    public static let slideUp   = SRKTransitionConfig(type: .slide(.up),     animation: .easeInOut(duration: 0.5))
    public static let slideDown = SRKTransitionConfig(type: .slide(.down),   animation: .easeInOut(duration: 0.5))
    public static let scale     = SRKTransitionConfig(type: .scale,          animation: .easeInOut(duration: 0.5))

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

@MainActor
public final class ScreenRouterKit {

    public static let shared = ScreenRouterKit()
    private init() {}

    private(set) var config: SRKConfiguration?
    private(set) var transitionConfig: SRKTransitionConfig = .fade
    private(set) var mainViewProvider: SRKMainViewProvider?
    private var viewModel: SRKRouterViewModel?
    private var started = false

    weak var _appDelegate: SRKAppDelegate?

    private(set) var splashSignal = SRKSplashSignal()

    public func present(
        transition: SRKTransitionConfig = .fade,
        splash: @escaping SRKSplashProvider,
        mainView: @escaping SRKMainViewProvider,
        debugMode: SRKDebugMode = .minimal,
        attHandling: SRKATTHandling,
        attDelay: TimeInterval,
        defaultOrientations: UIInterfaceOrientationMask = .portrait,
        webOrientations: UIInterfaceOrientationMask = .all
    ) -> some View {

        mainViewProvider    = mainView
        transitionConfig    = transition

        let config = SRKConfiguration(
            splash:              splash,
            debugMode:           debugMode,
            attHandling:         attHandling,
            attDelay:            attDelay,
            defaultOrientations: defaultOrientations,
            webOrientations:     webOrientations
        )

        configure(config)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.startSimple()
        }

        return makeRootView()
    }

    public func start(
        host: String,
        bundleID: String,
        splash: SRKSplashProvider?,
        mainView: SRKMainViewProvider?,
        debugMode: SRKDebugMode = .minimal,
        pushEnabled: Bool = true,
        attHandling: SRKATTHandling = .managedByLibrary,
        attDelay: TimeInterval,
        fallbackURL: String? = nil,
        nativeOnly: Bool = false,
        defaultOrientations: UIInterfaceOrientationMask = .portrait,
        webOrientations: UIInterfaceOrientationMask = .all
    ) -> some View {
        let base = "https://\(host.trimmingCharacters(in: .init(charactersIn: "/")))"
        return start(
            registerURL:         "\(base)/v1/public/install",
            syncURL:             "\(base)/v1/public/refresh",
            bundleID:            bundleID,
            splash:              splash,
            mainView:            mainView,
            debugMode:           debugMode,
            pushEnabled:         pushEnabled,
            attHandling:         attHandling,
            attDelay:            attDelay,
            fallbackURL:         fallbackURL,
            nativeOnly:          nativeOnly,
            defaultOrientations: defaultOrientations,
            webOrientations:     webOrientations
        )
    }

    public func start(
        registerURL: String,
        syncURL: String,
        bundleID: String,
        splash: SRKSplashProvider?,
        mainView: SRKMainViewProvider?,
        debugMode: SRKDebugMode = .minimal,
        pushEnabled: Bool = true,
        attHandling: SRKATTHandling = .managedByLibrary,
        attDelay: TimeInterval,
        fallbackURL: String? = nil,
        nativeOnly: Bool = false,
        defaultOrientations: UIInterfaceOrientationMask = .portrait,
        webOrientations: UIInterfaceOrientationMask = .all
    ) -> some View {

        mainViewProvider = mainView

        let config = SRKConfiguration(
            registerURL:         registerURL,
            syncURL:             syncURL,
            bundleID:            bundleID,
            attHandling:         attHandling,
            attDelay:            attDelay,
            splash:              splash,
            debugMode:           debugMode,
            pushEnabled:         pushEnabled,
            fallbackURL:         fallbackURL,
            defaultOrientations: defaultOrientations,
            webOrientations:     webOrientations,
            nativeOnly:          nativeOnly
        )

        configure(config)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.start()
        }

        return makeRootView()
    }

    public func startWithTracking(
        host: String,
        bundleID: String,
        splash: SRKSplashProvider?,
        mainView: SRKMainViewProvider?,
        debugMode: SRKDebugMode = .minimal,
        pushEnabled: Bool = true,
        attDelay: TimeInterval,
        fallbackURL: String? = nil,
        nativeOnly: Bool = false,
        defaultOrientations: UIInterfaceOrientationMask = .portrait,
        webOrientations: UIInterfaceOrientationMask = .all
    ) -> some View {
        let base = "https://\(host.trimmingCharacters(in: .init(charactersIn: "/")))"
        return startWithTracking(
            registerURL:         "\(base)/v1/public/install",
            syncURL:             "\(base)/v1/public/refresh",
            bundleID:            bundleID,
            splash:              splash,
            mainView:            mainView,
            debugMode:           debugMode,
            pushEnabled:         pushEnabled,
            attDelay:            attDelay,
            fallbackURL:         fallbackURL,
            nativeOnly:          nativeOnly,
            defaultOrientations: defaultOrientations,
            webOrientations:     webOrientations
        )
    }

    public func startWithTracking(
        registerURL: String,
        syncURL: String,
        bundleID: String,
        splash: SRKSplashProvider?,
        mainView: SRKMainViewProvider?,
        debugMode: SRKDebugMode = .minimal,
        pushEnabled: Bool = true,
        attDelay: TimeInterval,
        fallbackURL: String? = nil,
        nativeOnly: Bool = false,
        defaultOrientations: UIInterfaceOrientationMask = .portrait,
        webOrientations: UIInterfaceOrientationMask = .all
    ) -> some View {

        mainViewProvider = mainView

        let signal = SRKATTSignal()

        if let delegate = _appDelegate {
            delegate.attSignal        = signal
            delegate.appsFlyerEnabled = true
        } else {
            SRKLogger.log(.warning, "startWithTracking: _appDelegate not set yet")
        }

        let config = SRKConfiguration(
            registerURL:          registerURL,
            syncURL:              syncURL,
            bundleID:             bundleID,
            attSignal:            signal,
            appsFlyerIDProvider:  {
                UserDefaults.standard.string(forKey: "wbc.appsflyer.id")
            },
            attDelay:             attDelay,
            splash:               splash,
            debugMode:            debugMode,
            pushEnabled:          pushEnabled,
            fallbackURL:          fallbackURL,
            defaultOrientations:  defaultOrientations,
            webOrientations:      webOrientations,
            nativeOnly:           nativeOnly
        )

        configure(config)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.start()

            if let delegate = self._appDelegate {
                delegate.attSignal        = signal
                delegate.appsFlyerEnabled = true
                delegate.performATTForAppsFlyer()
            } else {
                SRKLogger.log(.warning, "startWithTracking asyncAfter: _appDelegate not found — completing ATT signal as false")
                signal.complete(authorized: false)
            }
        }

        return makeRootView()
    }

    public func configure(_ config: SRKConfiguration) {
        self.config = config
        SRKLogger.mode = config.debugMode
        SRKLogger.log(.info, "ScreenRouterKit: configure() bundleID=\(config.bundleID)")
    }

    public func makeRootView() -> some View {
        let vm = getOrCreateViewModel()
        return SRKRouterRootView().environmentObject(vm)
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
            let attGate = SRKATTGate(handling: config.attHandling, delay: config.attDelay)
            let attAuthorized = await attGate.requestIfNeeded()
            UserDefaults.standard.set(attAuthorized, forKey: "wbc.att.authorized")
            SRKLogger.log(.info, "ScreenRouterKit: startSimple — ATT authorized=\(attAuthorized)")
            viewModel?.setMain()
        }
    }

    public func handleAPNSToken(_ data: Data) {
        let hex = data.map { String(format: "%02.2hhx", $0) }.joined()
        SRKLogger.log(.info, "ScreenRouterKit: APNs (\(hex)")
        UserDefaults.standard.set(true, forKey: "wbcApnsReady")
        UserDefaults.standard.set(hex,  forKey: "wbcApnsTokenHex")
        SRKPushGate.shared.apnsToken = hex
        NotificationCenter.default.post(name: .wbcAPNSTokenDidUpdate, object: nil,
                                        userInfo: ["wbc_apns": hex])
    }

    public func handleFCMToken(_ token: String) {
        guard !token.isEmpty else { return }

        let isRefresh = started

        if isRefresh {
            SRKLogger.logKey(.fcmRefresh, "fcm_refresh=\(token)")
        } else {
            SRKLogger.logKey(.fcmFirst, "fcm_early=\(token)")
        }

        UserDefaults.standard.set(token, forKey: "wbc.fcm.token")
        SRKPushGate.shared.fcmToken = token
        NotificationCenter.default.post(name: .wbcFCMTokenDidUpdate, object: nil,
                                        userInfo: ["token": token])
    }

    public var currentOrientations: UIInterfaceOrientationMask {
        config?.defaultOrientations ?? .portrait
    }

    public var presented: SRKScene {
        viewModel?.presented ?? .loading
    }

    public var presentedPublisher: Published<SRKScene>.Publisher? {
        viewModel?.$presented
    }

    public func reset() {
        SRKLogger.log(.info, "ScreenRouterKit: reset()")
        [
            "wbc.flow.lock", "wbc.flow.url",
            "wbc.session.done", "wbc.session.fcm", "wbc.session.device",
            "wbc.att.authorized", "wbc.stable.uuid",
            "wbc.device.idfa", "wbc.appsflyer.id"
        ].forEach { UserDefaults.standard.removeObject(forKey: $0) }
        started          = false
        viewModel        = nil
        mainViewProvider = nil
        splashSignal     = SRKSplashSignal()
    }

    private func getOrCreateViewModel() -> SRKRouterViewModel {
        if let existing = viewModel { return existing }
        let vm = SRKRouterViewModel()
        viewModel = vm
        return vm
    }
}
