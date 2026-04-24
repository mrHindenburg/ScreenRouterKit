// SRKAppDelegate.swift
// ScreenRouterKit

import UIKit
import UserNotifications
import AppTrackingTransparency
import AdSupport


open class SRKAppDelegate: NSObject, UIApplicationDelegate {
    var attSignal: SRKATTSignal?
    var appsFlyerEnabled: Bool = false

    open func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        firebaseConfigure()
        if appsFlyerEnabled {
            appsFlyerConfigure()
        }
        SRKLogger.log(.debug, "AppDelegate: didFinishLaunching")
        return true
    }

    open func firebaseConfigure() {
        SRKLogger.log(.warning, "AppDelegate: firebaseConfigure() not overridden — Firebase not configured")
    }

    open func appsFlyerConfigure() {}

    open func attDidComplete(authorized: Bool) {}

    func performATTForAppsFlyer() {
        ATTrackingManager.requestTrackingAuthorization { [weak self] status in
            let authorized = (status == .authorized)

            if authorized {
                let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
                UserDefaults.standard.set(idfa, forKey: "wbc.device.idfa")
                SRKLogger.log(.info, "AppDelegate: IDFA saved")
            }

            if let afClass = NSClassFromString("AppsFlyerLib") as? NSObject.Type {
                let afInstance = afClass.value(forKeyPath: "shared") as AnyObject
                _ = afInstance.perform(NSSelectorFromString("start"))

                if let uid = afInstance.perform(NSSelectorFromString("getAppsFlyerUID"))?
                    .takeUnretainedValue() as? String {
                    UserDefaults.standard.set(uid, forKey: "wbc.appsflyer.id")
                    SRKLogger.log(.info, "AppDelegate: AppsFlyer UID saved")
                }
            }

            SRKLogger.log(.info, "AppDelegate: ATT completed — authorized=\(authorized)")
            self?.attDidComplete(authorized: authorized)
            self?.attSignal?.complete(authorized: authorized)
        }
    }

    open func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        ScreenRouterKit.shared.handleAPNSToken(deviceToken)
    }

    open func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        SRKLogger.log(.error, "AppDelegate: APNs error — \(error.localizedDescription)")
    }

    open func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        ScreenRouterKit.shared.currentOrientations
    }
}

extension SRKAppDelegate: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
    
    public func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            completionHandler()
        }
}
