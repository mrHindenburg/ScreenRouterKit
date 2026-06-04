import AppTrackingTransparency
import AdSupport
import ObjectiveC

final class SRKAppsFlyerFields {
    static let shared = SRKAppsFlyerFields()
    private init() {}

    private let lock = NSLock()
    private var conversionData: [AnyHashable: Any] = [:]

    func updateConversionData(_ data: [AnyHashable: Any]) {
        lock.withLock { conversionData = data }
    }

    func extraFields() -> [String: Any] {
        let snapshot: [AnyHashable: Any] = lock.withLock { conversionData }

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
        let sel = NSSelectorFromString("getAppsFlyerUID")
        guard instance.responds(to: sel) else { return nil }
        return instance.perform(sel)?.takeUnretainedValue() as? String
    }

    static func handleOpen(_ url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) {
        guard let afClass = NSClassFromString("AppsFlyerLib") as? NSObject.Type else { return }
        let instance = afClass.value(forKeyPath: "shared") as AnyObject
        // 7.0.0 selector is `handleOpenUrl:options:` (lowercase "rl"); the old
        // `handleOpen:options:` does not exist and would crash via perform().
        let sel = NSSelectorFromString("handleOpenUrl:options:")
        guard instance.responds(to: sel) else { return }
        _ = instance.perform(sel, with: url, with: options as AnyObject)
    }

    static func continueUserActivity(_ activity: NSUserActivity) {
        guard let afClass = NSClassFromString("AppsFlyerLib") as? NSObject.Type else { return }
        let instance = afClass.value(forKeyPath: "shared") as AnyObject
        let sel = NSSelectorFromString("continueUserActivity:restorationHandler:")
        guard instance.responds(to: sel) else { return }
        _ = instance.perform(sel, with: activity, with: nil)
    }

    static func setDebugMode(_ enabled: Bool) {
        guard let afClass = NSClassFromString("AppsFlyerLib") as? NSObject.Type else { return }
        let instance = afClass.value(forKeyPath: "shared") as AnyObject
        guard let cls = object_getClass(instance) else { return }

        // AppsFlyer 7.0.0 declares `isDebug` with a custom setter `-isDebug:`
        // (older SDKs used the default `-setIsDebug:`). KVC `setValue(_:forKey:"isDebug")`
        // only ever looks for `setIsDebug:`, so on 7.0.0 it silently misses the setter and
        // debug logging never turns on. Invoke whichever setter the SDK actually exposes.
        let candidates = [NSSelectorFromString("isDebug:"), NSSelectorFromString("setIsDebug:")]
        guard let sel = candidates.first(where: { class_getInstanceMethod(cls, $0) != nil }),
              let method = class_getInstanceMethod(cls, sel) else { return }

        typealias SetBoolIMP = @convention(c) (AnyObject, Selector, ObjCBool) -> Void
        let setter = unsafeBitCast(method_getImplementation(method), to: SetBoolIMP.self)
        setter(instance, sel, ObjCBool(enabled))
    }
}
