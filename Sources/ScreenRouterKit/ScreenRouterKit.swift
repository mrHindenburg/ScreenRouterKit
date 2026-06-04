import SwiftUI
import Combine

nonisolated public struct SRKTransitionConfig: Sendable {

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
    private var configuredForTracking = false

    weak var _appDelegate: SRKAppDelegate?

    private(set) var splashSignal = SRKSplashSignal()

    // MARK: - Scenario 1: Simple — splash + native view, no server

    public func present<S: View, M: View>(
        transition:          SRKTransitionConfig          = .fade,
        @ViewBuilder splash: @escaping (_ onComplete: @escaping () -> Void) -> S,
        @ViewBuilder mainView: @escaping () -> M,
        debugMode:           SRKDebugMode,
        defaultOrientations: UIInterfaceOrientationMask   = .portrait,
        webOrientations:     UIInterfaceOrientationMask   = .all
    ) -> some View {
        mainViewProvider = { AnyView(mainView()) }
        transitionConfig = transition

        let config = SRKConfiguration(
            splash:              { onComplete in AnyView(splash(onComplete)) },
            debugMode:           debugMode,
            defaultOrientations: defaultOrientations,
            webOrientations:     webOrientations
        )
        configure(config)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.startSimple()
        }
        return makeRootView()
    }

    // MARK: - Scenario 1b: Splash + native view + ATT + push (no server)

    public func presentWithPermissions<S: View, M: View>(
        transition:          SRKTransitionConfig          = .fade,
        @ViewBuilder splash: @escaping (_ onComplete: @escaping () -> Void) -> S,
        @ViewBuilder mainView: @escaping () -> M,
        debugMode:           SRKDebugMode,
        attHandling:         SRKATTHandling               = .managedByLibrary,
        attDelay:            TimeInterval                 = 0,
        pushEnabled:         Bool                         = true,
        defaultOrientations: UIInterfaceOrientationMask   = .portrait,
        webOrientations:     UIInterfaceOrientationMask   = .all
    ) -> some View {
        mainViewProvider = { AnyView(mainView()) }
        transitionConfig = transition

        let config = SRKConfiguration(
            splash:              { onComplete in AnyView(splash(onComplete)) },
            debugMode:           debugMode,
            attHandling:         attHandling,
            attDelay:            attDelay,
            pushEnabled:         pushEnabled,
            defaultOrientations: defaultOrientations,
            webOrientations:     webOrientations
        )
        configure(config)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.startSimple()
        }
        return makeRootView()
    }

    // MARK: - Scenario 2: Server registration only — no push, no ATT, no Firebase

    public func start<S: View, M: View>(
        host:                String,
        appId:               String,
        @ViewBuilder splash: @escaping (_ onComplete: @escaping () -> Void) -> S,
        @ViewBuilder mainView: @escaping () -> M,
        debugMode:           SRKDebugMode,
        transition:          SRKTransitionConfig          = .fade,
        fallbackURL:         String?                      = nil,
        nativeOnly:          Bool                         = false,
        defaultOrientations: UIInterfaceOrientationMask   = .portrait,
        webOrientations:     UIInterfaceOrientationMask   = .all
    ) -> some View {
        mainViewProvider = { AnyView(mainView()) }
        transitionConfig = transition

        let base = "https://\(host.trimmingCharacters(in: .init(charactersIn: "/")))"
        let config = SRKConfiguration(
            registerURL:         "\(base)/v1/public/install",
            syncURL:             "\(base)/v1/public/refresh",
            appId:               appId,
            attHandling:         .skip,
            attDelay:            0,
            splash:              { onComplete in AnyView(splash(onComplete)) },
            debugMode:           debugMode,
            pushEnabled:         false,
            fallbackURL:         fallbackURL,
            defaultOrientations: defaultOrientations,
            webOrientations:     webOrientations,
            nativeOnly:          nativeOnly
        )
        configure(config)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.start() }
        return makeRootView()
    }

    // MARK: - Scenario 3: Server + Firebase push + ATT (no AppsFlyer)

    public func startWithPush<S: View, M: View>(
        host:                String,
        appId:               String,
        @ViewBuilder splash: @escaping (_ onComplete: @escaping () -> Void) -> S,
        @ViewBuilder mainView: @escaping () -> M,
        debugMode:           SRKDebugMode,
        transition:          SRKTransitionConfig          = .fade,
        attDelay:            TimeInterval                 = 2.0,
        fallbackURL:         String?                      = nil,
        nativeOnly:          Bool                         = false,
        defaultOrientations: UIInterfaceOrientationMask   = .portrait,
        webOrientations:     UIInterfaceOrientationMask   = .all
    ) -> some View {
        mainViewProvider = { AnyView(mainView()) }
        transitionConfig = transition

        let base = "https://\(host.trimmingCharacters(in: .init(charactersIn: "/")))"
        let config = SRKConfiguration(
            registerURL:         "\(base)/v1/public/install",
            syncURL:             "\(base)/v1/public/refresh",
            appId:               appId,
            attHandling:         .managedByLibrary,
            attDelay:            attDelay,
            splash:              { onComplete in AnyView(splash(onComplete)) },
            debugMode:           debugMode,
            pushEnabled:         true,
            fallbackURL:         fallbackURL,
            defaultOrientations: defaultOrientations,
            webOrientations:     webOrientations,
            nativeOnly:          nativeOnly
        )
        configure(config)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.start() }
        return makeRootView()
    }

    // MARK: - Scenario 4: Server + Firebase push + ATT + AppsFlyer

    public func startWithTracking<S: View, M: View>(
        host:                String,
        appId:               String,
        @ViewBuilder splash: @escaping (_ onComplete: @escaping () -> Void) -> S,
        @ViewBuilder mainView: @escaping () -> M,
        debugMode:           SRKDebugMode,
        transition:          SRKTransitionConfig          = .fade,
        attDelay:            TimeInterval                 = 2.0,
        fallbackURL:         String?                      = nil,
        nativeOnly:          Bool                         = false,
        defaultOrientations: UIInterfaceOrientationMask   = .portrait,
        webOrientations:     UIInterfaceOrientationMask   = .all
    ) -> some View {
        guard !configuredForTracking else { return makeRootView() }
        configuredForTracking = true

        mainViewProvider = { AnyView(mainView()) }
        transitionConfig = transition

        let signal         = SRKATTSignal()
        let appsFlyerSignal = SRKAppsFlyerSignal()

        if let delegate = _appDelegate {
            delegate.attSignal        = signal
            delegate.appsFlyerSignal  = appsFlyerSignal
            delegate.appsFlyerEnabled = true
        } else {
            SRKLogger.log(.warning, "startWithTracking: _appDelegate not set yet")
        }

        let base = "https://\(host.trimmingCharacters(in: .init(charactersIn: "/")))"
        let config = SRKConfiguration(
            registerURL:                "\(base)/v1/public/install",
            syncURL:                    "\(base)/v1/public/refresh",
            appId:                      appId,
            attSignal:                  signal,
            attDelay:                   attDelay,
            appsFlyerSignal:            appsFlyerSignal,
            appsFlyerIDProvider:        { UserDefaults.standard.string(forKey: "wbc.appsflyer.id") },
            splash:                     { onComplete in AnyView(splash(onComplete)) },
            debugMode:                  debugMode,
            pushEnabled:                true,
            fallbackURL:                fallbackURL,
            defaultOrientations:        defaultOrientations,
            webOrientations:            webOrientations,
            nativeOnly:                 nativeOnly,
            extraInstallFieldsProvider: SRKAppsFlyerFields.shared.extraFields
        )
        configure(config)
        SRKAppsFlyerFields.setDebugMode(debugMode == .verbose)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.start() }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1 + attDelay) {
            if let delegate = self._appDelegate {
                delegate.performATTForAppsFlyer()
            } else {
                SRKLogger.log(.warning, "startWithTracking asyncAfter: _appDelegate not found — completing ATT signal as false")
                signal.complete(authorized: false)
            }
        }

        return makeRootView()
    }

    // MARK: - Internal

    func configure(_ config: SRKConfiguration) {
        self.config = config
        SRKLogger.mode = config.debugMode
        SRKLogger.appsFlyerEnabled = config.appsFlyerIDProvider != nil
        SRKLogger.log(.info, "ScreenRouterKit: configure() appId=\(config.appId)")
    }

    func makeRootView() -> some View {
        let vm = getOrCreateViewModel()
        return SRKRouterRootView().environmentObject(vm)
    }

    func start() {
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

            if config.pushEnabled {
                try? await Task.sleep(nanoseconds: 600_000_000)
                await SRKPushGate.shared.requestPermissionOnly()
            }

            viewModel?.setMain()
        }
    }

    func handleAPNSToken(_ data: Data) {
        let hex = data.map { String(format: "%02.2hhx", $0) }.joined()
        SRKLogger.log(.info, "ScreenRouterKit: APNs (\(hex)")
        UserDefaults.standard.set(true, forKey: "wbcApnsReady")
        UserDefaults.standard.set(hex,  forKey: "wbcApnsTokenHex")
        SRKPushGate.shared.apnsToken = hex
        NotificationCenter.default.post(name: .wbcAPNSTokenDidUpdate, object: nil,
                                        userInfo: ["wbc_apns": hex])
    }

    func handleFCMToken(_ token: String) {
        guard !token.isEmpty else { return }
        SRKLogger.log(.debug, "FCM token \(started ? "refresh" : "early"): \(token)")
        UserDefaults.standard.set(token, forKey: "wbc.fcm.token")
        SRKPushGate.shared.fcmToken = token
        NotificationCenter.default.post(name: .wbcFCMTokenDidUpdate, object: nil,
                                        userInfo: ["token": token])
    }

    var currentOrientations: UIInterfaceOrientationMask {
        config?.defaultOrientations ?? .portrait
    }

    var presented: SRKScene {
        viewModel?.presented ?? .loading
    }

    var presentedPublisher: Published<SRKScene>.Publisher? {
        viewModel?.$presented
    }

    func reset() {
        SRKLogger.log(.info, "ScreenRouterKit: reset()")
        [
            "wbc.flow.lock", "wbc.flow.url",
            "wbc.session.done", "wbc.session.fcm", "wbc.session.device",
            "wbc.att.authorized", "wbc.stable.uuid",
            "wbc.device.idfa", "wbc.appsflyer.id"
        ].forEach { UserDefaults.standard.removeObject(forKey: $0) }
        started               = false
        configuredForTracking = false
        viewModel             = nil
        mainViewProvider      = nil
        splashSignal          = SRKSplashSignal()
    }

    private func getOrCreateViewModel() -> SRKRouterViewModel {
        if let existing = viewModel { return existing }
        let vm = SRKRouterViewModel()
        viewModel = vm
        return vm
    }
}
