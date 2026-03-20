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

public final class SRKSplashSignal: @unchecked Sendable {

    private var continuation: CheckedContinuation<Void, Never>?
    private let lock = NSLock()
    private var completed = false

    public init() {}

    public func complete() {
        lock.lock()
        let cont = continuation
        completed = true
        continuation = nil
        lock.unlock()
        cont?.resume()
    }

    func wait() async {
        lock.lock()
        let alreadyDone = completed
        lock.unlock()
        if alreadyDone { return }

        await withCheckedContinuation { cont in
            lock.lock()
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

/// Universal splash provider — always receives onComplete callback.
/// Call onComplete() when your splash animation finishes.
/// Works identically in Simple, Full-A, and Full-B modes —
/// switching modes never requires changing SplashView.
public typealias SRKSplashProvider = (_ onComplete: @escaping () -> Void) -> AnyView

/// Main view provider.
public typealias SRKMainViewProvider = () -> AnyView

// MARK: - AppsFlyer ID Provider

public typealias SRKAppsFlyerIDProvider = () -> String?

// MARK: - Launch Mode

public enum SRKLaunchMode: Sendable {
    case simple
    case full(registerURL: String, syncURL: String, bundleID: String)
}

// MARK: - Configuration

public struct SRKConfiguration: @unchecked Sendable {

    // MARK: Properties

    public let launchMode:          SRKLaunchMode
    public let registerURL:         String
    public let syncURL:             String
    public let bundleID:            String
    public let attHandling:         SRKATTHandling

    /// Delay in seconds before the ATT alert is shown.
    /// Useful to let the splash animation finish before the system dialog appears.
    /// Applies only to `.managedByLibrary` — ignored for `.skip` and `.managedByHost`.
    /// Default: `0` (no delay).
    public let attDelay:            TimeInterval

    public let appsFlyerIDProvider: SRKAppsFlyerIDProvider?
    public let pushEnabled:         Bool
    public let fallbackURL:         String?

    /// Universal splash provider — same type for all modes.
    public let splashProvider:      SRKSplashProvider?

    public let debugMode:           SRKDebugMode
    public let defaultOrientations: UIInterfaceOrientationMask
    public let webOrientations:     UIInterfaceOrientationMask

    // MARK: - Simple init

    public init(
        splash:              @escaping SRKSplashProvider,
        debugMode:           SRKDebugMode                    = .disabled,
        attHandling:         SRKATTHandling                  = .skip,
        attDelay:            TimeInterval                    = 0.5,
        defaultOrientations: UIInterfaceOrientationMask      = .portrait,
        webOrientations:     UIInterfaceOrientationMask      = .all
    ) {
        self.launchMode          = .simple
        self.registerURL         = ""
        self.syncURL             = ""
        self.bundleID            = ""
        self.attHandling         = attHandling
        self.attDelay            = attDelay
        self.appsFlyerIDProvider = nil
        self.pushEnabled         = false
        self.fallbackURL         = nil
        self.splashProvider      = splash
        self.debugMode           = debugMode
        self.defaultOrientations = defaultOrientations
        self.webOrientations     = webOrientations
    }

    // MARK: - Full init — Variant A (without AppsFlyer)

    public init(
        registerURL:         String,
        syncURL:             String,
        bundleID:            String,
        attHandling:         SRKATTHandling                  = .managedByLibrary,
        attDelay:            TimeInterval                    = 0.5,
        splash:              SRKSplashProvider?               = nil,
        debugMode:           SRKDebugMode                    = .disabled,
        pushEnabled:         Bool                            = true,
        fallbackURL:         String?                         = nil,
        defaultOrientations: UIInterfaceOrientationMask      = .portrait,
        webOrientations:     UIInterfaceOrientationMask      = .all
    ) {
        self.launchMode          = .full(registerURL: registerURL, syncURL: syncURL, bundleID: bundleID)
        self.registerURL         = registerURL
        self.syncURL             = syncURL
        self.bundleID            = bundleID
        self.attHandling         = attHandling
        self.attDelay            = attDelay
        self.appsFlyerIDProvider = nil
        self.pushEnabled         = pushEnabled
        self.fallbackURL         = fallbackURL
        self.splashProvider      = splash
        self.debugMode           = debugMode
        self.defaultOrientations = defaultOrientations
        self.webOrientations     = webOrientations
    }

    // MARK: - Full init — Variant B (with AppsFlyer)

    public init(
        registerURL:         String,
        syncURL:             String,
        bundleID:            String,
        attSignal:           SRKATTSignal,
        appsFlyerIDProvider: @escaping SRKAppsFlyerIDProvider,
        attDelay:            TimeInterval                    = 0.5,
        splash:              SRKSplashProvider?               = nil,
        debugMode:           SRKDebugMode                    = .disabled,
        pushEnabled:         Bool                            = true,
        fallbackURL:         String?                         = nil,
        defaultOrientations: UIInterfaceOrientationMask      = .portrait,
        webOrientations:     UIInterfaceOrientationMask      = .all
    ) {
        self.launchMode          = .full(registerURL: registerURL, syncURL: syncURL, bundleID: bundleID)
        self.registerURL         = registerURL
        self.syncURL             = syncURL
        self.bundleID            = bundleID
        self.attHandling         = .managedByHost(signal: attSignal)
        self.attDelay            = attDelay
        self.appsFlyerIDProvider = appsFlyerIDProvider
        self.pushEnabled         = pushEnabled
        self.fallbackURL         = fallbackURL
        self.splashProvider      = splash
        self.debugMode           = debugMode
        self.defaultOrientations = defaultOrientations
        self.webOrientations     = webOrientations
    }
}
