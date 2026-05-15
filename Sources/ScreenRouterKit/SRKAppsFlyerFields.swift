import AppTrackingTransparency
import UIKit
import AdSupport

final class SRKAppsFlyerFields {
    static let shared = SRKAppsFlyerFields()
    private init() {}

    private let lock = NSLock()
    private var conversionData: [AnyHashable: Any] = [:]

    func updateConversionData(_ data: [AnyHashable: Any]) {
        lock.lock()
        conversionData = data
        lock.unlock()
    }

    func extraFields() -> [String: Any] {
        lock.lock()
        let snapshot = conversionData
        lock.unlock()

        var fields: [String: Any] = [
            "appsInfo": buildAppsInfo(from: snapshot),
            "timezone": TimeZone.autoupdatingCurrent.identifier,
            "language": Locale.preferredLanguages.first ?? Locale.current.identifier
        ]

        if let idfa = advertiserId() {
            fields["advertiser_id"] = idfa
        } else if let uid = appsFlyerUID(), !uid.isEmpty {
            fields["advertiser_id"] = uid
        }

        return fields
    }

    private func buildAppsInfo(from data: [AnyHashable: Any]) -> [String: Any] {
        guard !data.isEmpty else { return [:] }
        var result: [String: Any] = [:]
        for (key, value) in data {
            let k = String(describing: key)
            if k == "iscache" || k == "CB_preload_equal_priority_enabled" {
                if let b = value as? Bool {
                    result[k] = b
                } else if let s = value as? String {
                    result[k] = (s as NSString).boolValue
                } else {
                    result[k] = value
                }
            } else {
                result[k] = (value as? String) ?? String(describing: value)
            }
        }
        return result
    }

    private func advertiserId() -> String? {
        guard ATTrackingManager.trackingAuthorizationStatus == .authorized else { return nil }
        let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
        guard idfa != "00000000-0000-0000-0000-000000000000" else { return nil }
        return idfa
    }

    private func appsFlyerUID() -> String? {
        guard let afClass = NSClassFromString("AppsFlyerLib") as? NSObject.Type else { return nil }
        let instance = afClass.value(forKeyPath: "shared") as AnyObject
        return instance.perform(NSSelectorFromString("getAppsFlyerUID"))?
            .takeUnretainedValue() as? String
    }

    static func handleOpen(_ url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) {
        guard let afClass = NSClassFromString("AppsFlyerLib") as? NSObject.Type else { return }
        let instance = afClass.value(forKeyPath: "shared") as AnyObject
        _ = instance.perform(NSSelectorFromString("handleOpen:options:"), with: url, with: options as AnyObject)
    }

    static func continueUserActivity(_ activity: NSUserActivity) {
        guard let afClass = NSClassFromString("AppsFlyerLib") as? NSObject.Type else { return }
        let instance = afClass.value(forKeyPath: "shared") as AnyObject
        _ = instance.perform(NSSelectorFromString("continueUserActivity:restorationHandler:"), with: activity, with: nil)
    }

    static func setDebugMode(_ enabled: Bool) {
        guard let afClass = NSClassFromString("AppsFlyerLib") as? NSObject.Type,
              let instance = afClass.value(forKeyPath: "shared") as? NSObject else { return }
        instance.setValue(NSNumber(value: enabled), forKey: "isDebug")
    }
}
