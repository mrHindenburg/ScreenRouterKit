// SRKConfiguration.swift
// ScreenRouterKit

import UIKit
import SwiftUI

// MARK: - ATT Handling

public enum SRKATTHandling: Sendable {
    /// Library shows the ATT alert itself.
    /// Variant A — without AppsFlyer.
    case managedByLibrary

    /// Host shows the ATT alert and signals via SRKATTSignal.
    /// Variant B — with AppsFlyer.
    case managedByHost(signal: SRKATTSignal)

    /// ATT is not requested.
    case skip
}

// MARK: - ATT Signal

/// Channel between host app and library for variant B.
/// ⚠️ Store as @State or AppDelegate property — NOT as a local variable.
public final class SRKATTSignal: @unchecked Sendable {

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

// MARK: - Splash Signal

/// Channel between SplashView and library.
/// SplashView calls complete() when its animation finishes.
/// ⚠️ Store as @State — NOT as a local variable.
public final class SRKSplashSignal: @unchecked Sendable {

    private var continuation: CheckedContinuation<Void, Never>?
    private let lock = NSLock()
    private var completed = false

    public init() {}

    /// Call this from SplashView when animation is done.
    public func complete() {
        lock.lock()
        let cont = continuation
        completed = true
        continuation = nil
        lock.unlock()
        cont?.resume()
    }

    func wait() async {
        // Already completed before we started waiting — return immediately
        lock.lock()
        let alreadyDone = completed
        lock.unlock()
        if alreadyDone { return }

        await withCheckedContinuation { cont in
            lock.lock()
            // Double-check after acquiring lock
            if completed {
                lock.unlock()
                cont.resume()
            } else {
                continuation = cont
                lock.unlock()
            }
        }
    }
}

// MARK: - View Providers

/// Splash provider for simple start — receives onComplete callback.
/// Call onComplete() when splash animation is finished.
public typealias SRKSplashProviderSimple = (_ onComplete: @escaping () -> Void) -> AnyView

/// Splash provider for full start — no callback, library controls dismissal.
public typealias SRKSplashProvider = () -> AnyView

/// Main view provider.
public typealias SRKMainViewProvider = () -> AnyView

// MARK: - AppsFlyer ID Provider

public typealias SRKAppsFlyerIDProvider = () -> String?

// MARK: - Launch Mode

/// Determines which pipeline the library runs.
public enum SRKLaunchMode: Sendable {

    /// Simple mode — no networking, no ATT, no push.
    /// Library shows splash, waits for onComplete(), then fades to mainView.
    case simple

    /// Full mode — runs ATT → Push → POST /register pipeline.
    case full(registerURL: String, syncURL: String, bundleID: String)
}

// MARK: - Configuration

public struct SRKConfiguration: @unchecked Sendable {

    // MARK: Launch Mode

    public let launchMode: SRKLaunchMode

    // MARK: Full mode only

    public let registerURL: String
    public let syncURL: String
    public let bundleID: String
    public let attHandling: SRKATTHandling
    public let appsFlyerIDProvider: SRKAppsFlyerIDProvider?
    public let pushEnabled: Bool
    public let fallbackURL: String?

    // MARK: UI

    /// Used in full mode — no callback.
    public let splashProvider: SRKSplashProvider?

    /// Used in simple mode — receives onComplete callback.
    public let splashProviderSimple: SRKSplashProviderSimple?

    // MARK: Settings

    public let debugMode: SRKDebugMode
    public let defaultOrientations: UIInterfaceOrientationMask
    public let webOrientations: UIInterfaceOrientationMask

    // MARK: - Simple init

    public init(
        splash:   @escaping SRKSplashProviderSimple,
        debugMode: SRKDebugMode = .disabled,
        attHandling: SRKATTHandling = .managedByLibrary,
        defaultOrientations: UIInterfaceOrientationMask = .portrait,
        webOrientations: UIInterfaceOrientationMask = .all
    ) {
        self.launchMode            = .simple
        self.registerURL            = ""
        self.syncURL            = ""
        self.bundleID              = ""
        self.attHandling           = attHandling
        self.appsFlyerIDProvider   = nil
        self.pushEnabled           = false
        self.fallbackURL           = nil
        self.splashProvider        = nil
        self.splashProviderSimple  = splash
        self.debugMode             = debugMode
        self.defaultOrientations   = defaultOrientations
        self.webOrientations       = webOrientations
    }

    // MARK: - Full init — Variant A (without AppsFlyer)

    public init(
        registerURL: String,
        syncURL: String,
        bundleID: String,
        attHandling: SRKATTHandling = .managedByLibrary,
        splash: SRKSplashProvider? = nil,
        debugMode: SRKDebugMode = .disabled,
        pushEnabled: Bool = true,
        fallbackURL: String? = nil,
        defaultOrientations: UIInterfaceOrientationMask = .portrait,
        webOrientations: UIInterfaceOrientationMask = .all
    ) {
        self.launchMode            = .full(registerURL: registerURL, syncURL: syncURL, bundleID: bundleID)
        self.registerURL            = registerURL
        self.syncURL            = syncURL
        self.bundleID              = bundleID
        self.attHandling           = attHandling
        self.appsFlyerIDProvider   = nil
        self.pushEnabled           = pushEnabled
        self.fallbackURL           = fallbackURL
        self.splashProvider        = splash
        self.splashProviderSimple  = nil
        self.debugMode             = debugMode
        self.defaultOrientations   = defaultOrientations
        self.webOrientations       = webOrientations
    }

    // MARK: - Full init — Variant B (with AppsFlyer)

    public init(
        registerURL: String,
        syncURL: String,
        bundleID: String,
        attSignal: SRKATTSignal,
        appsFlyerIDProvider: @escaping SRKAppsFlyerIDProvider,
        splash: SRKSplashProvider? = nil,
        debugMode: SRKDebugMode = .disabled,
        pushEnabled: Bool = true,
        fallbackURL: String? = nil,
        defaultOrientations: UIInterfaceOrientationMask = .portrait,
        webOrientations: UIInterfaceOrientationMask = .all
    ) {
        self.launchMode            = .full(registerURL: registerURL, syncURL: syncURL, bundleID: bundleID)
        self.registerURL            = registerURL
        self.syncURL            = syncURL
        self.bundleID              = bundleID
        self.attHandling           = .managedByHost(signal: attSignal)
        self.appsFlyerIDProvider   = appsFlyerIDProvider
        self.pushEnabled           = pushEnabled
        self.fallbackURL           = fallbackURL
        self.splashProvider        = splash
        self.splashProviderSimple  = nil
        self.debugMode             = debugMode
        self.defaultOrientations   = defaultOrientations
        self.webOrientations       = webOrientations
    }
}
