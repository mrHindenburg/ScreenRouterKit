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

// MARK: - 1. Simple Mode (без сервера, тільки сплеш + нативний екран)

/*
 Використовується коли немає бекенду — тільки сплеш і нативний MainView.
 ATT пропускається (.skip).
 Firebase і push не потрібні.
*/

struct SRKExample_SimpleApp: App {
    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.present(
                transition:  .slideUp,
                splash: { onComplete in
                    AnyView(MySplashView(onComplete: onComplete))
                },
                mainView: {
                    AnyView(MyMainView())
                },
                debugMode:   .minimal,
                attHandling: .skip,
                attDelay:    0
            )
        }
    }
}

// MARK: - 2. Full Mode (з сервером, з Firebase, без AppsFlyer)

/*
 Стандартна інтеграція з бекендом і Firebase FCM.
 ATT керується бібліотекою автоматично.
 Важливо: FirebaseAppDelegateProxyEnabled = NO в Info.plist.
*/

struct SRKExample_FullApp: App {
    @UIApplicationDelegateAdaptor(SRKExample_FullAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.start(
                host:        "api.myapp.com",
                appId:       "com.mycompany.app",
                splash: { onComplete in
                    AnyView(MySplashView(onComplete: onComplete))
                },
                mainView: {
                    AnyView(MyMainView())
                },
                debugMode:   .minimal,
                pushEnabled: true,
                attHandling: .managedByLibrary,
                attDelay:    1.5
            )
        }
    }
}

final class SRKExample_FullAppDelegate: SRKAppDelegate, MessagingDelegate {

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

// MARK: - 3. Full Mode (з сервером, з Firebase, з AppsFlyer)

/*
 Використовується коли потрібен AppsFlyer + ATT + IDFA.

 Що SRK робить автоматично (вам НЕ потрібно):
   - .onOpenURL / .onContinueUserActivity — SRK передає URL в AppsFlyer сам
   - extraInstallFields — AppsFlyer conversion data збирається і вставляється автоматично
   - attHandling — ATT завжди управляється через AppDelegate

 Обов'язкові кроки:
   1. appsFlyerEnabled = true  в didFinishLaunchingWithOptions (ДО super)
   2. ScreenRouterKit.shared._appDelegate = self  (до SwiftUI body)
   3. super.application(...) обов'язково — запускає Firebase, AppsFlyer, push
*/

struct SRKExample_TrackingApp: App {
    @UIApplicationDelegateAdaptor(SRKExample_TrackingAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.startWithTracking(
                host:        "api.myapp.com",
                appId:       "com.mycompany.app",
                splash: { onComplete in
                    AnyView(MySplashView(onComplete: onComplete))
                },
                mainView: {
                    AnyView(MyMainView())
                },
                debugMode:   .minimal,
                pushEnabled: true,
                attDelay:    2.0   // ATT діалог з'явиться через 1с (старт) + 2с (attDelay) = ~3с
            )
        }
    }
}

final class SRKExample_TrackingAppDelegate: SRKAppDelegate, MessagingDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        appsFlyerEnabled = true                      // вмикаємо AppsFlyer ДО super
        ScreenRouterKit.shared._appDelegate = self   // реєструємо до SwiftUI body
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func firebaseConfigure() {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
    }

    override func appsFlyerConfigure() {
        AppsFlyerLib.shared().appsFlyerDevKey = "YOUR_DEV_KEY"
        AppsFlyerLib.shared().appleAppID      = "YOUR_APP_ID"
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
        // викликається після того як ATT діалог закрився
        // authorized == true означає що IDFA доступний
    }
}

extension SRKExample_TrackingAppDelegate: AppsFlyerLibDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        // SRK сам зберігає conversion data і завершує сигнал — просто делегуємо
        onAppsFlyerConversionData(conversionInfo)
    }
    func onConversionDataFail(_ error: Error) {
        onAppsFlyerConversionFail()
    }
}

// MARK: - Placeholder Views (замінити своїми)

private struct MySplashView: View {
    let onComplete: () -> Void
    var body: some View { Text("Splash") }
}

private struct MyMainView: View {
    var body: some View { Text("Main App") }
}
