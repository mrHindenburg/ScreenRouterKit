// SRKAppDelegate.swift
// ScreenRouterKit

import UserNotifications
import AppTrackingTransparency
import AdSupport


open class SRKAppDelegate: NSObject, UIApplicationDelegate {
    var attSignal: SRKATTSignal?
    var appsFlyerSignal: SRKAppsFlyerSignal?
    var appsFlyerEnabled: Bool = false

    open func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        ScreenRouterKit.shared._appDelegate = self
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

    public func didReceiveFCMToken(_ token: String) {
        ScreenRouterKit.shared.handleFCMToken(token)
    }

    public func onAppsFlyerConversionData(_ data: [AnyHashable: Any]) {
        SRKAppsFlyerFields.shared.updateConversionData(data)
        appsFlyerSignal?.complete()
    }

    public func onAppsFlyerConversionFail() {
        appsFlyerSignal?.complete()
    }

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
                let uidSel = NSSelectorFromString("getAppsFlyerUID")

                if afInstance.responds(to: uidSel),
                   let uid = afInstance.perform(uidSel)?.takeUnretainedValue() as? String {
                    UserDefaults.standard.set(uid, forKey: "wbc.appsflyer.id")
                    SRKLogger.af(.info, "AppDelegate: AppsFlyer UID saved")
                }
            }

            SRKLogger.log(.info, "AppDelegate: ATT completed — authorized=\(authorized)")
            self?.attDidComplete(authorized: authorized)
            self?.attSignal?.complete(authorized: authorized)
        }
    }

    open func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        SRKLogger.log(.info, "AppDelegate: open URL — \(url)")
        if appsFlyerEnabled {
            SRKAppsFlyerFields.handleOpen(url, options: options)
        }
        return true
    }

    open func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        SRKLogger.log(.info, "AppDelegate: continue userActivity — \(userActivity.webpageURL?.absoluteString ?? "no webpageURL")")
        if appsFlyerEnabled {
            SRKAppsFlyerFields.continueUserActivity(userActivity)
        }
        return true
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
