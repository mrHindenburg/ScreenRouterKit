// SRKATTGate.swift
// ScreenRouterKit

import AppTrackingTransparency

final class SRKATTGate: Sendable {

    private let handling: SRKATTHandling

    init(handling: SRKATTHandling) {
        self.handling = handling
    }

    /// Requests ATT authorization according to the configured strategy.
    /// Always completes — either after the user responds or immediately (skip).
    func requestIfNeeded() async -> Bool {
        switch handling {

        case .skip:
            SRKLogger.log(.debug, "ATT: skip")
            return false

        case .managedByHost(let signal):
            SRKLogger.log(.debug, "ATT: waiting for host signal...")
            let authorized = await signal.wait()
            SRKLogger.log(.info, "ATT: host signaled — authorized=\(authorized)")
            return authorized

        case .managedByLibrary:
            SRKLogger.log(.debug, "ATT: requesting via library")

            let status = await MainActor.run {
                ATTrackingManager.trackingAuthorizationStatus
            }

            // Already determined — skip showing the alert again
            if status != .notDetermined {
                let authorized = (status == .authorized)
                SRKLogger.log(.info, "ATT: already determined — authorized=\(authorized)")
                return authorized
            }

            return await withCheckedContinuation { continuation in
                ATTrackingManager.requestTrackingAuthorization { status in
                    let authorized = (status == .authorized)
                    SRKLogger.log(.info, "ATT: response — authorized=\(authorized)")
                    continuation.resume(returning: authorized)
                }
            }
        }
    }
}
