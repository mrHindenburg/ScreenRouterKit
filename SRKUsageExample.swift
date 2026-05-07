// SRKUsageExamples.swift
// ScreenRouterKit — Usage Examples
//
// Цей файл містить приклади інтеграції бібліотеки.
// Не включати в production target — тільки для довідки.

import SwiftUI
import AppsFlyerLib

// MARK: - 1. Simple Mode (без сервера, тільки сплеш + нативний екран)

/*
 Використовується коли немає бекенду — тільки сплеш і нативний MainView.
 ATT можна увімкнути або пропустити.
*/

struct SRKExample_SimpleApp: App {
    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.present(
                transition: .slideUp,
                splash: { onComplete in
                    AnyView(
                        MySplashView(onComplete: onComplete)
                    )
                },
                mainView: {
                    AnyView(MyMainView())
                },
                debugMode: .minimal,
                attHandling: .skip,
                attDelay: 1.5
            )
        }
    }
}

// MARK: - 1-A. Full Mode (з сервером, без Firebase,без AppsFlyer)
struct SRKExample_FullApp: App {
    @UIApplicationDelegateAdaptor(SRKExample_FullAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.start(
                host: "api.myapp.com",
                bundleID: "",
                splash: { onComplete in
                    AnyView(MySplashView(onComplete: onComplete))
                },
                mainView: {
                    AnyView(MyMainView())
                },
                debugMode: .minimal,
                pushEnabled: false,
                attHandling: .skip,
                attDelay: 1.5,
                nativeOnly: false
            )
        }
    }
}


// MARK: - 2. Full Mode (з сервером, з Firebase, без AppsFlyer)

/*
 Стандартна інтеграція з бекендом.
 ATT керується бібліотекою автоматично.
 Firebase треба сконфігурувати в AppDelegate.
*/

@main
struct SRKExample_FullApp: App {
    @UIApplicationDelegateAdaptor(SRKExample_FullAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.start(
                host: "api.myapp.com",
                bundleID: "",
                splash: { onComplete in
                    AnyView(MySplashView(onComplete: onComplete))
                },
                mainView: {
                    AnyView(MyMainView())
                },
                debugMode: .minimal,
                pushEnabled: true,
                attHandling: .managedByLibrary,
                attDelay: 1.5,
                nativeOnly: false
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
        Messaging.messaging().apnsToken = deviceToken        // спочатку Firebase
        ScreenRouterKit.shared.handleAPNSToken(deviceToken)  // потім бібліотека
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
 Використовується коли потрібен AppsFlyer + ATT.
 ATT керується AppDelegate через performATTForAppsFlyer().
 AppDelegate обов'язково має бути зареєстрований до виклику startWithTracking.
*/

@main
struct SRKExample_TrackingApp: App {
    @UIApplicationDelegateAdaptor(SRKExample_TrackingAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.startWithTracking(
                host: "api.myapp.com",
                bundleID: "",
                splash: { onComplete in
                    AnyView(MySplashView(onComplete: onComplete))
                },
                mainView: {
                    AnyView(MyMainView())
                },
                debugMode: .minimal,
                pushEnabled: true,
                attDelay: 2.0,
                nativeOnly: false
            )
        }
    }
}

final class SRKExample_TrackingAppDelegate: SRKAppDelegate, MessagingDelegate {
 
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        appsFlyerEnabled = true
        ScreenRouterKit.shared._appDelegate = self
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
    }
 
    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken        // спочатку Firebase
        ScreenRouterKit.shared.handleAPNSToken(deviceToken)  // потім бібліотека
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
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {}
    func onConversionDataFail(_ error: Error) {}
}


// MARK: - Placeholder Views (замінити своїми)

private struct MySplashView: View {
    let onComplete: () -> Void
    var body: some View {
        Text("Splash View")
    }
}

private struct MyMainView: View {
    var body: some View {
        Text("Main App View")
    }
}
