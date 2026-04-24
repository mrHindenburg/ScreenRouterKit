import UIKit
import SwiftUI

public enum SRKATTHandling: Sendable {
    case managedByLibrary
    case managedByHost(signal: SRKATTSignal)
    case skip
}

public final class SRKATTSignal: @unchecked Sendable {

    private var continuation: CheckedContinuation<Bool, Never>?
    private let lock = NSLock()
    private var storedResult: Bool?

    public init() {}

    public func complete(authorized: Bool) {
        lock.lock()
        let cont = continuation
        continuation = nil
        if cont == nil {
            storedResult = authorized
        }
        lock.unlock()
        cont?.resume(returning: authorized)
    }

    func wait() async -> Bool {
        lock.lock()
        if let result = storedResult {
            lock.unlock()
            return result
        }
        return await withCheckedContinuation { cont in
            continuation = cont
            lock.unlock()
        }
    }
}

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

public typealias SRKSplashProvider    = (_ onComplete: @escaping () -> Void) -> AnyView
public typealias SRKMainViewProvider  = () -> AnyView
public typealias SRKAppsFlyerIDProvider = () -> String?

public enum SRKLaunchMode: Sendable {
    case simple
    case full(registerURL: String, syncURL: String, bundleID: String)
}

public struct SRKConfiguration: @unchecked Sendable {

    public let launchMode:          SRKLaunchMode
    public let registerURL:         String
    public let syncURL:             String
    public let bundleID:            String
    public let attHandling:         SRKATTHandling
    public let attDelay:            TimeInterval
    public let appsFlyerIDProvider: SRKAppsFlyerIDProvider?
    public let pushEnabled:         Bool
    public let fallbackURL:         String?
    public let splashProvider:      SRKSplashProvider?
    public let debugMode:           SRKDebugMode
    public let defaultOrientations: UIInterfaceOrientationMask
    public let webOrientations:     UIInterfaceOrientationMask
    public let nativeOnly:          Bool

    public init(
        splash:              @escaping SRKSplashProvider,
        debugMode:           SRKDebugMode               = .disabled,
        attHandling:         SRKATTHandling              = .skip,
        attDelay:            TimeInterval,
        defaultOrientations: UIInterfaceOrientationMask = .portrait,
        webOrientations:     UIInterfaceOrientationMask = .all,
        nativeOnly:          Bool                       = false
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
        self.nativeOnly          = nativeOnly
    }

    public init(
        registerURL:         String,
        syncURL:             String,
        bundleID:            String,
        attHandling:         SRKATTHandling              = .managedByLibrary,
        attDelay:            TimeInterval,
        splash:              SRKSplashProvider?          = nil,
        debugMode:           SRKDebugMode               = .disabled,
        pushEnabled:         Bool                       = true,
        fallbackURL:         String?                    = nil,
        defaultOrientations: UIInterfaceOrientationMask = .portrait,
        webOrientations:     UIInterfaceOrientationMask = .all,
        nativeOnly:          Bool                       = false
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
        self.nativeOnly          = nativeOnly
    }

    public init(
        registerURL:         String,
        syncURL:             String,
        bundleID:            String,
        attSignal:           SRKATTSignal,
        appsFlyerIDProvider: @escaping SRKAppsFlyerIDProvider,
        attDelay:            TimeInterval,
        splash:              SRKSplashProvider?          = nil,
        debugMode:           SRKDebugMode               = .disabled,
        pushEnabled:         Bool                       = true,
        fallbackURL:         String?                    = nil,
        defaultOrientations: UIInterfaceOrientationMask = .portrait,
        webOrientations:     UIInterfaceOrientationMask = .all,
        nativeOnly:          Bool                       = false
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
        self.nativeOnly          = nativeOnly
    }
}

