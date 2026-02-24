// WLKATTGate.swift
// ScreenRouterKit

import AppTrackingTransparency

final class WLKATTGate: Sendable {

    private let handling: WLKATTHandling

    init(handling: WLKATTHandling) {
        self.handling = handling
    }

    /// Requests ATT authorization according to the configured strategy.
    /// Always completes — either after the user responds or immediately (skip).
    func requestIfNeeded() async -> Bool {
        switch handling {

        case .skip:
            WLKLogger.log(.debug, "ATT: skip")
            return false

        case .managedByHost(let signal):
            WLKLogger.log(.debug, "ATT: waiting for host signal...")
            let authorized = await signal.wait()
            WLKLogger.log(.info, "ATT: host signaled — authorized=\(authorized)")
            return authorized

        case .managedByLibrary:
            WLKLogger.log(.debug, "ATT: requesting via library")

            let status = await MainActor.run {
                ATTrackingManager.trackingAuthorizationStatus
            }

            // Already determined — skip showing the alert again
            if status != .notDetermined {
                let authorized = (status == .authorized)
                WLKLogger.log(.info, "ATT: already determined — authorized=\(authorized)")
                return authorized
            }

            return await withCheckedContinuation { continuation in
                ATTrackingManager.requestTrackingAuthorization { status in
                    let authorized = (status == .authorized)
                    WLKLogger.log(.info, "ATT: response — authorized=\(authorized)")
                    continuation.resume(returning: authorized)
                }
            }
        }
    }
}
