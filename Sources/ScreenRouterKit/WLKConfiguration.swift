// WLKConfiguration.swift
// ScreenRouterKit

import UIKit
import SwiftUI

// MARK: - ATT Handling

public enum WLKATTHandling: Sendable {
    /// Library shows the ATT alert itself.
    /// Variant A — without AppsFlyer.
    case managedByLibrary

    /// Host shows the ATT alert and signals via WLKATTSignal.
    /// Variant B — with AppsFlyer.
    case managedByHost(signal: WLKATTSignal)

    /// ATT is not requested.
    case skip
}

// MARK: - ATT Signal

/// Channel between host app and library for variant B.
/// Store as @State or AppDelegate property — NOT as a local variable.
public final class WLKATTSignal: @unchecked Sendable {

    private var continuation: CheckedContinuation<Bool, Never>?
    private let lock = NSLock()

    public init() {}

    public func complete(authorized: Bool) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: authorized)
    }

    func wait() async -> Bool {
        await withCheckedContinuation { cont in
            lock.lock()
            continuation = cont
            lock.unlock()
        }
    }
}

// MARK: - AppsFlyer ID Provider

public typealias WLKAppsFlyerIDProvider = () -> String?

// MARK: - Splash Provider

/// Closure returning a custom splash view.
/// Can return any SwiftUI View.
public typealias WLKSplashProvider = () -> AnyView

// MARK: - Configuration

public struct WLKConfiguration: @unchecked Sendable {

    // MARK: Required

    public let installURL: String
    public let refreshURL: String
    public let bundleID: String

    // MARK: ATT

    public let attHandling: WLKATTHandling

    // MARK: AppsFlyer

    public let appsFlyerIDProvider: WLKAppsFlyerIDProvider?

    // MARK: UI

    /// Custom splash shown during loading.
    /// If nil — library shows a plain system background.
    public let splashProvider: WLKSplashProvider?

    // MARK: Settings

    public let debugMode: WLKDebugMode
    public let pushEnabled: Bool
    public let fallbackURL: String?
    public let defaultOrientations: UIInterfaceOrientationMask
    public let webOrientations: UIInterfaceOrientationMask

    // MARK: - Variant A — without AppsFlyer

    public init(
        installURL: String,
        refreshURL: String,
        bundleID: String,
        attHandling: WLKATTHandling = .managedByLibrary,
        splashProvider: WLKSplashProvider? = nil,
        debugMode: WLKDebugMode = .disabled,
        pushEnabled: Bool = true,
        fallbackURL: String? = nil,
        defaultOrientations: UIInterfaceOrientationMask = .portrait,
        webOrientations: UIInterfaceOrientationMask = .all
    ) {
        self.installURL          = installURL
        self.refreshURL          = refreshURL
        self.bundleID            = bundleID
        self.attHandling         = attHandling
        self.appsFlyerIDProvider = nil
        self.splashProvider      = splashProvider
        self.debugMode           = debugMode
        self.pushEnabled         = pushEnabled
        self.fallbackURL         = fallbackURL
        self.defaultOrientations = defaultOrientations
        self.webOrientations     = webOrientations
    }

    // MARK: - Variant B — with AppsFlyer

    public init(
        installURL: String,
        refreshURL: String,
        bundleID: String,
        attSignal: WLKATTSignal,
        appsFlyerIDProvider: @escaping WLKAppsFlyerIDProvider,
        splashProvider: WLKSplashProvider? = nil,
        debugMode: WLKDebugMode = .disabled,
        pushEnabled: Bool = true,
        fallbackURL: String? = nil,
        defaultOrientations: UIInterfaceOrientationMask = .portrait,
        webOrientations: UIInterfaceOrientationMask = .all
    ) {
        self.installURL          = installURL
        self.refreshURL          = refreshURL
        self.bundleID            = bundleID
        self.attHandling         = .managedByHost(signal: attSignal)
        self.appsFlyerIDProvider = appsFlyerIDProvider
        self.splashProvider      = splashProvider
        self.debugMode           = debugMode
        self.pushEnabled         = pushEnabled
        self.fallbackURL         = fallbackURL
        self.defaultOrientations = defaultOrientations
        self.webOrientations     = webOrientations
    }
}
