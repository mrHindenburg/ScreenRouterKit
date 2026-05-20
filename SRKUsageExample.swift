// SRKUsageExamples.swift
// ScreenRouterKit — Usage Examples
//
// Цей файл містить приклади інтеграції бібліотеки.
// Не включати в production target — тільки для довідки.
// @main тут відсутній — один файл не може мати кілька точок входу.

import SwiftUI
import AppsFlyerLib
import Firebase
import FirebaseMessaging

// MARK: - AppConstants
//
// Єдине місце де зберігаються всі ідентифікатори застосунку.
// Скопіюйте в окремий AppConstants.swift.

enum AppConstants {
    static let appId     = "YOUR_APP_ID"            // App Store Connect numeric ID
    static let afDevKey  = "YOUR_APPSFLYER_DEV_KEY" // AppsFlyer Dev Key (тільки сценарій 4)
    static let host      = "YOUR_DOMAIN"            // без https://, напр. "api.myapp.com"
}

// MARK: - Сценарій 1: present() — тільки сплеш + нативний екран, без сервера
//
// Коли використовувати: немає бекенду, потрібен лише сплеш перед нативним MainView.
// AppDelegate не потрібен. Firebase і push не потрібні.
// ATT пропускається автоматично.

struct SRKExample_SimpleApp: App {
    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.present(
                transition: .slideUp,
                splash:     { onComplete in
                    MySplashView(onComplete: onComplete)
                },
                mainView:   { MyMainView() },
                debugMode:  .minimal
            )
        }
    }
}

// MARK: - Сценарій 2: start() — сервер без push і без ATT
//
// Коли використовувати: є бекенд для вибору маршруту (нативний/веб),
// але push-сповіщення і ATT не потрібні.
// AppDelegate не потрібен. Firebase не потрібен.

struct SRKExample_ServerApp: App {
    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.start(
                host:      AppConstants.host,
                appId:     AppConstants.appId,
                splash:    { onComplete in
                    MySplashView(onComplete: onComplete)
                },
                mainView:  { MyMainView() },
                debugMode: .minimal
            )
        }
    }
}

// MARK: - Сценарій 3: startWithPush() — сервер + push + ATT (Firebase FCM, без AppsFlyer)
//
// Коли використовувати: є бекенд, потрібні push-сповіщення через Firebase FCM і ATT.
// AppsFlyer не потрібен.
// Важливо: FirebaseAppDelegateProxyEnabled = NO в Info.plist.

struct SRKExample_PushApp: App {
    @UIApplicationDelegateAdaptor(SRKExample_PushAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.startWithPush(
                host:      AppConstants.host,
                appId:     AppConstants.appId,
                splash:    { onComplete in
                    MySplashView(onComplete: onComplete)
                },
                mainView:  { MyMainView() },
                debugMode: .minimal,
                attDelay:  1.5  // ATT діалог через 1с (старт) + 1.5с = ~2.5с
            )
        }
    }
}

final class SRKExample_PushAppDelegate: SRKAppDelegate, MessagingDelegate {

    override func firebaseConfigure() {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
    }

    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken       // спочатку Firebase
        ScreenRouterKit.shared.handleAPNSToken(deviceToken) // потім бібліотека
    }

    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        SRKLogger.log(.error, "APNs error — \(error.localizedDescription)")
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        ScreenRouterKit.shared.handleFCMToken(token)
    }
}

// MARK: - Сценарій 4: startWithTracking() — сервер + push + ATT + AppsFlyer (повна інтеграція)
//
// Коли використовувати: потрібен весь стек — сервер, Firebase FCM, ATT, IDFA і AppsFlyer.
//
// AppConstants.appId використовується двічі автоматично:
//   - AppsFlyerLib.shared().appleAppID = AppConstants.appId  (в AppDelegate)
//   - appId: AppConstants.appId                              (в startWithTracking)
// Достатньо змінити один рядок в AppConstants.swift.
//
// Що SRK робить автоматично (вам НЕ потрібно робити вручну):
//   - .onOpenURL / .onContinueUserActivity — SRK передає URL в AppsFlyer сам
//   - extraInstallFields — AppsFlyer conversion data збирається і вставляється автоматично
//   - ATT — управляється через AppDelegate
//
// Обов'язкові кроки в AppDelegate:
//   1. appsFlyerEnabled = true            — ДО super.application(...)
//   2. ScreenRouterKit.shared._appDelegate = self  — ДО super.application(...)
//   3. super.application(...)             — обов'язково, запускає Firebase, AppsFlyer, push

struct SRKExample_TrackingApp: App {
    @UIApplicationDelegateAdaptor(SRKExample_TrackingAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.startWithTracking(
                host:      AppConstants.host,
                appId:     AppConstants.appId,
                splash:    { onComplete in MySplashView(onComplete: onComplete) },
                mainView:  { MyMainView() },
                debugMode: .minimal,
                attDelay:  2.0  // ATT діалог через 1с (старт) + 2с = ~3с
            )
        }
    }
}

final class SRKExample_TrackingAppDelegate: SRKAppDelegate, MessagingDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        appsFlyerEnabled = true                      // обов'язково ДО super
        ScreenRouterKit.shared._appDelegate = self   // обов'язково ДО super
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func firebaseConfigure() {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
    }

    override func appsFlyerConfigure() {
        AppsFlyerLib.shared().appsFlyerDevKey = AppConstants.afDevKey
        AppsFlyerLib.shared().appleAppID      = AppConstants.appId   // той самий що в startWithTracking
        AppsFlyerLib.shared().delegate        = self
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 60)
        AppsFlyerLib.shared().start()
    }

    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken       // спочатку Firebase
        ScreenRouterKit.shared.handleAPNSToken(deviceToken) // потім бібліотека
    }

    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        SRKLogger.log(.error, "APNs error — \(error.localizedDescription)")
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        ScreenRouterKit.shared.handleFCMToken(token)
    }

    override func attDidComplete(authorized: Bool) {
        // authorized == true — IDFA доступний
    }
}

extension SRKExample_TrackingAppDelegate: AppsFlyerLibDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        onAppsFlyerConversionData(conversionInfo) // SRK зберігає і вставляє в /install сам
    }
    func onConversionDataFail(_ error: Error) {
        onAppsFlyerConversionFail()
    }
}

// MARK: - Placeholder Views (суто для прикладу)

private struct MySplashView: View {
    let onComplete: () -> Void
    var body: some View { Text("Splash") }
}

private struct MyMainView: View {
    var body: some View { Text("Main App") }
}
