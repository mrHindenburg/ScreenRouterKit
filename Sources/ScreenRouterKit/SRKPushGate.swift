// SRKPushGate.swift
// ScreenRouterKit

import UIKit
import UserNotifications

// MARK: - Push Gate

final class SRKPushGate: Sendable {

    // MARK: Shared token storage
    // Updated from AppDelegate via ScreenRouterKit.shared.handleFCMToken / handleAPNSToken

    static let shared = SRKPushGate(enabled: true)

    private let enabled: Bool

    // Thread-safe token storage
    private let _fcmToken = TokenBox()
    private let _srk_apnsToken = TokenBox()

    var fcmToken: String? {
        get { _fcmToken.value }
        set { _fcmToken.value = newValue }
    }

    var srk_apnsToken: String? {
        get { _srk_apnsToken.value }
        set { _srk_apnsToken.value = newValue }
    }

    init(enabled: Bool) {
        self.enabled = enabled
    }

    // MARK: - Request Permission

    /// Requests push notification permission (if pushEnabled = true).
    /// Then waits for a stable FCM token with debounce logic.
    /// Always returns — either a stable token or nil after timeout.
    func requestAndCollect() async -> String? {
        if enabled {
            await requestPermission()
        } else {
            SRKLogger.log(.debug, "Push: permission request skipped (pushEnabled=false)")
        }

        // Register for remote notifications (required for FCM)
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }

        // Wait for stable FCM token
        return await waitForStableFCMToken()
    }

    /// Optimistic variant — requests permission and registers APNs so Firebase
    /// starts fetching the FCM token in the background, then returns immediately.
    /// Does NOT wait for the token. The coordinator polls via waitForFCMToken()
    /// and falls back to /sync when the token eventually arrives.
    func requestPermissionOnly() async {
        if enabled {
            await requestPermission()
        } else {
            SRKLogger.log(.debug, "Push: permission request skipped (pushEnabled=false)")
        }
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
        SRKLogger.log(.debug, "Push: permission requested — token will arrive async")
    }

    // MARK: - Private

    private func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let current = await center.notificationSettings()

        guard current.authorizationStatus == .notDetermined else {
            SRKLogger.log(.debug, "Push: already authorized — status=\(current.authorizationStatus.rawValue)")
            return
        }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            SRKLogger.log(.info, "Push: user responded — granted=\(granted)")
        } catch {
            SRKLogger.log(.error, "Push: permission request error — \(error.localizedDescription)")
        }
    }

    /// Waits for a stable FCM token using debounce logic.
    /// - Waits at least `minWindowSeconds` after the first token arrives
    /// - Accepts token only after it hasn't changed for `debounceSeconds`
    /// - Falls back to cached token after `maxWindowSeconds`
    private func waitForStableFCMToken(
        minWindowSeconds: Double = 4.0,
        debounceSeconds:  Double = 1.2,
        maxWindowSeconds: Double = 8.0
    ) async -> String? {

        SRKLogger.log(.debug, "Push: waiting for stable FCM token (min=\(minWindowSeconds)s, debounce=\(debounceSeconds)s, max=\(maxWindowSeconds)s)")

        let start    = Date()
        let deadline = start.addingTimeInterval(maxWindowSeconds)

        var latestToken: String? = nil
        var lastChange:  Date   = .distantPast

        // ── Seed from shared/UserDefaults if already available ────────────
        if let existing = SRKPushGate.shared.fcmToken, !existing.isEmpty {
            latestToken = existing
            lastChange  = Date()
            SRKLogger.log(.debug, "Push: seeded token from shared: \(existing)")
        } else if let stored = UserDefaults.standard.string(forKey: "srk.fcm.token"), !stored.isEmpty {
            latestToken = stored
            lastChange  = Date()
            SRKLogger.log(.debug, "Push: seeded token from UserDefaults")
        }

        // ── Wait for first token if not seeded ────────────────────────────
        while latestToken == nil || latestToken!.isEmpty {
            if Date() > deadline { break }

            if let t = SRKPushGate.shared.fcmToken, !t.isEmpty {
                latestToken = t
                lastChange  = Date()
                SRKLogger.log(.debug, "Push: first token captured from shared")
                break
            }

            if let t = UserDefaults.standard.string(forKey: "srk.fcm.token"), !t.isEmpty {
                latestToken = t
                lastChange  = Date()
                SRKLogger.log(.debug, "Push: first token captured from UserDefaults")
                break
            }

            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        guard let _ = latestToken else {
            SRKLogger.log(.warning, "Push: no FCM token received — sending empty")
            return nil
        }

        let firstTokenTime = Date()
        SRKLogger.log(.debug, "Push: first token captured — starting stability window")

        // ── Stability loop ────────────────────────────────────────────────
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 150_000_000)

            // Check for newer token
            let current = SRKPushGate.shared.fcmToken
                ?? UserDefaults.standard.string(forKey: "srk.fcm.token")

            if let current, !current.isEmpty, current != latestToken {
                SRKLogger.log(.debug, "Push: FCM changed: \(latestToken ?? "nil") → \(current)")
                latestToken = current
                lastChange  = Date()
            }

            let sinceFirst  = Date().timeIntervalSince(firstTokenTime)
            let sinceChange = Date().timeIntervalSince(lastChange)

            // Must wait minimum window AND token must be stable
            if sinceFirst >= minWindowSeconds,
               let tok = latestToken, !tok.isEmpty,
               sinceChange >= debounceSeconds {
                SRKLogger.log(.info, "Push: stable FCM token accepted (sinceFirst=\(String(format: "%.1f", sinceFirst))s, sinceChange=\(String(format: "%.1f", sinceChange))s)")
                return tok
            }
        }

        // ── Timeout fallback ──────────────────────────────────────────────
        let fallback = latestToken
            ?? SRKPushGate.shared.fcmToken
            ?? UserDefaults.standard.string(forKey: "srk.fcm.token")

        if let fallback, !fallback.isEmpty {
            SRKLogger.log(.warning, "Push: stability timeout — using best available token")
            return fallback
        }

        SRKLogger.log(.warning, "Push: FCM token not received within \(maxWindowSeconds)s — sending empty")
        return nil
    }
}

// MARK: - TokenBox (thread-safe storage)

/// NSLock-based wrapper for thread-safe string read/write
final class TokenBox: @unchecked Sendable {
    private var _value: String?
    private let lock = NSLock()

    var value: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}

