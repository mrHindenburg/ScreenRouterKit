//
//  AppDelegate.swift
//  ScreenRouterKit
//
//  Created by Tymur Batulin on 23.02.2026.
//


// WLKAppDelegate.swift
// ScreenRouterKit

import UIKit
import UserNotifications
import AppTrackingTransparency
import AdSupport

// MARK: - WLKAppDelegate

/// ── Ver A - no  AppsFlyer
/// ```swift
/// import FirebaseCore
/// import FirebaseMessaging
/// import ScreenRouterKit
///
/// final class AppDelegate: WLKAppDelegate, MessagingDelegate {
///
///     override func firebaseConfigure() {
///         FirebaseApp.configure()
///         Messaging.messaging().delegate = self
///     }
///     func messaging(_ messaging: Messaging,
///                    didReceiveRegistrationToken fcmToken: String?) {
///         guard let token = fcmToken else { return }
///         ScreenRouterKit.shared.handleFCMToken(token)
///     }
///
/// }
/// ```
///
/// ── Ver B - with AppsFlyer) ──────────────────────────────────────────────────
/// ```swift
/// import FirebaseCore
/// import FirebaseMessaging
/// import AppsFlyerLib
/// import ScreenRouterKit
///
/// final class AppDelegate: WLKAppDelegate, MessagingDelegate, AppsFlyerLibDelegate {
///
///     override func firebaseConfigure() {
///         FirebaseApp.configure()
///         Messaging.messaging().delegate = self
///     }
///
///     override func appsFlyerConfigure() {
///         AppsFlyerLib.shared().appsFlyerDevKey = "YOUR_DEV_KEY"
///         AppsFlyerLib.shared().appleAppID      = "YOUR_APPLE_APP_ID"
///         AppsFlyerLib.shared().delegate        = self
///     }
///
///     func messaging(_ messaging: Messaging,
///                    didReceiveRegistrationToken fcmToken: String?) {
///         guard let token = fcmToken else { return }
///         ScreenRouterKit.shared.handleFCMToken(token)
///     }
///
///      func onConversionDataSuccess(_ info: [AnyHashable: Any]) {}
///      func onConversionDataFail(_ error: Error) {}
/// }
/// ```
open class WLKAppDelegate: NSObject, UIApplicationDelegate {

    // MARK: - Internal State

    /// ATT Signal for variant B — set by ScreenRouterKit.shared.launchWithAppsFlyer(...)
    var attSignal: WLKATTSignal?

    /// Whether AppsFlyer is enabled — set automatically by launchWithAppsFlyer()
    var appsFlyerEnabled: Bool = false

    // MARK: - didFinishLaunching

    open func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // Host overrides these methods and provides its keys
        firebaseConfigure()

        if appsFlyerEnabled {
            appsFlyerConfigure()
        }

        WLKLogger.log(.debug, "AppDelegate: didFinishLaunching")
        return true
    }

    // MARK: - Override Points

    /// Override and add FirebaseApp.configure() + Messaging.messaging().delegate = self
    open func firebaseConfigure() {
        // Empty by default — override in host
        WLKLogger.log(.warning, "AppDelegate: firebaseConfigure() not overridden — Firebase not configured")
    }

    /// Override and add AppsFlyerLib keys (variant B only)
    /// Do NOT call AppsFlyerLib.shared().start() here — it will be called after ATT
    open func appsFlyerConfigure() {
        // Empty by default — override in host if using AppsFlyer
    }

    /// Override for custom logic after ATT (rarely needed)
    open func attDidComplete(authorized: Bool) {
        // Empty by default
    }

    // MARK: - ATT (internal)

    /// Called by ScreenRouterKit.shared.launchWithAppsFlyer()
    func performATTForAppsFlyer() {
        ATTrackingManager.requestTrackingAuthorization { [weak self] status in
            let authorized = (status == .authorized)

            // 1. Save IDFA if authorized
            if authorized {
                let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
                UserDefaults.standard.set(idfa, forKey: "wlk.device.idfa")
                WLKLogger.log(.info, "AppDelegate: IDFA saved")
            }

            // 2. Start AppsFlyer — IDFA is already available
            // Called via reflection to avoid importing AppsFlyerLib into the library
            if let afClass = NSClassFromString("AppsFlyerLib") as? NSObject.Type {
                let afInstance = afClass.value(forKeyPath: "shared") as AnyObject
                _ = afInstance.perform(NSSelectorFromString("start"))

                // Store AppsFlyer UID for /install request body
                if let uid = afInstance.perform(NSSelectorFromString("getAppsFlyerUID"))?
                    .takeUnretainedValue() as? String {
                    UserDefaults.standard.set(uid, forKey: "wlk.appsflyer.id")
                    WLKLogger.log(.info, "AppDelegate: AppsFlyer UID saved")
                }
            }

            WLKLogger.log(.info, "AppDelegate: ATT completed — authorized=\(authorized)")
            self?.attDidComplete(authorized: authorized)

            // 3. Unblock the pipeline
            self?.attSignal?.complete(authorized: authorized)
        }
    }

    // MARK: - APNs

    open func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        WLKLogger.log(.info, "AppDelegate: APNs token received")
        // Forward to Messaging via reflection to avoid importing Firebase into the library
        if let messagingClass = NSClassFromString("FIRMessaging") as? NSObject.Type {
            let instance = messagingClass.value(forKeyPath: "messaging") as AnyObject
            instance.setValue(deviceToken, forKey: "APNSToken")
        }
        ScreenRouterKit.shared.handleAPNSToken(deviceToken)
    }

    open func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        WLKLogger.log(.error, "AppDelegate: APNs error — \(error.localizedDescription)")
    }

    // MARK: - Orientation

    open func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        ScreenRouterKit.shared.currentOrientations
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension WLKAppDelegate: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
