import UIKit
import SwiftUI

public enum SRKATTHandling: Sendable {
    case managedByLibrary
    case managedByHost(signal: SRKATTSignal)
    case skip
}

public final class SRKATTSignal: @unchecked Sendable {

    private let lock = NSLock()
    nonisolated(unsafe) private var _result: Bool?
    nonisolated(unsafe) private var _streamCont: AsyncStream<Bool>.Continuation?
    private let _stream: AsyncStream<Bool>

    public init() {
        var cont: AsyncStream<Bool>.Continuation!
        _stream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
        _streamCont = cont
    }

    public nonisolated func complete(authorized: Bool) {
        let cont: AsyncStream<Bool>.Continuation? = lock.withLock {
            guard _result == nil else { return nil }
            _result = authorized
            let c = _streamCont
            _streamCont = nil
            return c
        }
        cont?.yield(authorized)
        cont?.finish()
    }

    nonisolated func wait() async -> Bool {
        if let r = lock.withLock({ _result }) { return r }
        for await value in _stream { return value }
        return lock.withLock { _result ?? false }
    }
}

public final class SRKSplashSignal: @unchecked Sendable {

    private let lock = NSLock()
    nonisolated(unsafe) private var _completed = false
    nonisolated(unsafe) private var _streamCont: AsyncStream<Void>.Continuation?
    private let _stream: AsyncStream<Void>

    public init() {
        var cont: AsyncStream<Void>.Continuation!
        _stream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
        _streamCont = cont
    }

    public nonisolated func complete() {
        let cont: AsyncStream<Void>.Continuation? = lock.withLock {
            guard !_completed else { return nil }
            _completed = true
            let c = _streamCont
            _streamCont = nil
            return c
        }
        cont?.yield(())
        cont?.finish()
    }

    nonisolated func wait() async {
        if lock.withLock({ _completed }) { return }
        for await _ in _stream { return }
    }
}

public final class SRKAppsFlyerSignal: @unchecked Sendable {

    private let lock = NSLock()
    nonisolated(unsafe) private var _completed = false
    nonisolated(unsafe) private var _streamCont: AsyncStream<Void>.Continuation?
    private let _stream: AsyncStream<Void>

    public init() {
        var cont: AsyncStream<Void>.Continuation!
        _stream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
        _streamCont = cont
    }

    public nonisolated func complete() {
        let cont: AsyncStream<Void>.Continuation? = lock.withLock {
            guard !_completed else { return nil }
            _completed = true
            let c = _streamCont
            _streamCont = nil
            return c
        }
        cont?.yield(())
        cont?.finish()
    }

    nonisolated func wait() async {
        if lock.withLock({ _completed }) { return }
        for await _ in _stream { return }
    }
}

public typealias SRKSplashProvider    = (_ onComplete: @escaping () -> Void) -> AnyView
public typealias SRKMainViewProvider  = () -> AnyView
public typealias SRKAppsFlyerIDProvider = () -> String?
public typealias SRKExtraInstallFieldsProvider = () -> [String: Any]

public struct SRKConfiguration: @unchecked Sendable {

    public let registerURL:                String
    public let syncURL:                    String
    public let appId:                   String
    public let attHandling:                SRKATTHandling
    public let attDelay:                   TimeInterval
    public let appsFlyerSignal:            SRKAppsFlyerSignal?
    public let appsFlyerIDProvider:        SRKAppsFlyerIDProvider?
    public let extraInstallFieldsProvider: SRKExtraInstallFieldsProvider?
    public let pushEnabled:                Bool
    public let fallbackURL:                String?
    public let splashProvider:             SRKSplashProvider?
    public let debugMode:                  SRKDebugMode
    public let defaultOrientations:        UIInterfaceOrientationMask
    public let webOrientations:            UIInterfaceOrientationMask
    public let nativeOnly:                 Bool

    public init(
        splash:              @escaping SRKSplashProvider,
        debugMode:           SRKDebugMode               = .disabled,
        attHandling:         SRKATTHandling              = .skip,
        attDelay:            TimeInterval               = 0,
        pushEnabled:         Bool                       = false,
        defaultOrientations: UIInterfaceOrientationMask = .portrait,
        webOrientations:     UIInterfaceOrientationMask = .all,
        nativeOnly:          Bool                       = false
    ) {
        self.registerURL                = ""
        self.syncURL                    = ""
        self.appId                      = ""
        self.attHandling                = attHandling
        self.attDelay                   = attDelay
        self.appsFlyerSignal            = nil
        self.appsFlyerIDProvider        = nil
        self.extraInstallFieldsProvider = nil
        self.pushEnabled                = pushEnabled
        self.fallbackURL                = nil
        self.splashProvider             = splash
        self.debugMode                  = debugMode
        self.defaultOrientations        = defaultOrientations
        self.webOrientations            = webOrientations
        self.nativeOnly                 = nativeOnly
    }

    public init(
        registerURL:                String,
        syncURL:                    String,
        appId:                      String,
        attHandling:                SRKATTHandling                  = .managedByLibrary,
        attDelay:                   TimeInterval,
        splash:                     SRKSplashProvider?              = nil,
        debugMode:                  SRKDebugMode                   = .disabled,
        pushEnabled:                Bool                           = true,
        fallbackURL:                String?                        = nil,
        defaultOrientations:        UIInterfaceOrientationMask     = .portrait,
        webOrientations:            UIInterfaceOrientationMask     = .all,
        nativeOnly:                 Bool                           = false,
        extraInstallFieldsProvider: SRKExtraInstallFieldsProvider? = nil
    ) {
        self.registerURL                = registerURL
        self.syncURL                    = syncURL
        self.appId                      = appId
        self.attHandling                = attHandling
        self.attDelay                   = attDelay
        self.appsFlyerSignal            = nil
        self.appsFlyerIDProvider        = nil
        self.extraInstallFieldsProvider = extraInstallFieldsProvider
        self.pushEnabled                = pushEnabled
        self.fallbackURL                = fallbackURL
        self.splashProvider             = splash
        self.debugMode                  = debugMode
        self.defaultOrientations        = defaultOrientations
        self.webOrientations            = webOrientations
        self.nativeOnly                 = nativeOnly
    }

    public init(
        registerURL:                String,
        syncURL:                    String,
        appId:                      String,
        attSignal:                  SRKATTSignal,
        attDelay:                   TimeInterval,
        appsFlyerSignal:            SRKAppsFlyerSignal?             = nil,
        appsFlyerIDProvider:        @escaping SRKAppsFlyerIDProvider,
        splash:                     SRKSplashProvider?              = nil,
        debugMode:                  SRKDebugMode                   = .disabled,
        pushEnabled:                Bool                           = true,
        fallbackURL:                String?                        = nil,
        defaultOrientations:        UIInterfaceOrientationMask     = .portrait,
        webOrientations:            UIInterfaceOrientationMask     = .all,
        nativeOnly:                 Bool                           = false,
        extraInstallFieldsProvider: SRKExtraInstallFieldsProvider? = nil
    ) {
        self.registerURL                = registerURL
        self.syncURL                    = syncURL
        self.appId                      = appId
        self.attHandling                = .managedByHost(signal: attSignal)
        self.attDelay                   = attDelay
        self.appsFlyerSignal            = appsFlyerSignal
        self.appsFlyerIDProvider        = appsFlyerIDProvider
        self.extraInstallFieldsProvider = extraInstallFieldsProvider
        self.pushEnabled                = pushEnabled
        self.fallbackURL                = fallbackURL
        self.splashProvider             = splash
        self.debugMode                  = debugMode
        self.defaultOrientations        = defaultOrientations
        self.webOrientations            = webOrientations
        self.nativeOnly                 = nativeOnly
    }
}
