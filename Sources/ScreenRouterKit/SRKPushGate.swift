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
    private let _fcmToken  = TokenBox()
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
    /// Then waits for the FCM token with a timeout.
    /// Always returns — either a token or nil after timeout.
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

        // Wait for FCM token
        return await waitForFCMToken()
    }

    // MARK: - Private

    private func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let current = await center.notificationSettings()

        // Already answered — do not show the alert again
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

    private func waitForFCMToken(timeoutSeconds: Double = 6.0) async -> String? {
        SRKLogger.log(.debug, "Push: waiting for FCM token (timeout=\(timeoutSeconds)s)")

        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            // Check in-memory first (updated from AppDelegate)
            if let token = fcmToken, !token.isEmpty {
                SRKLogger.log(.info, "Push: FCM token received")
                return token
            }

            // Fallback — UserDefaults (may have been saved by AppDelegate earlier)
            if let stored = UserDefaults.standard.string(forKey: "srk.fcm.token"), !stored.isEmpty {
                SRKLogger.log(.debug, "Push: FCM token from UserDefaults")
                fcmToken = stored
                return stored
            }

            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
        }

        // Last chance after timeout
        let fallback = UserDefaults.standard.string(forKey: "srk.fcm.token")
        if let fallback, !fallback.isEmpty {
            SRKLogger.log(.warning, "Push: FCM token from fallback after timeout")
            return fallback
        }

        SRKLogger.log(.warning, "Push: FCM token not received within \(timeoutSeconds)s — sending empty")
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
