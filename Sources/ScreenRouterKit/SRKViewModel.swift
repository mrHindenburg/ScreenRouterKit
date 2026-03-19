// SRKViewModel.swift
// ScreenRouterKit

import SwiftUI
import Combine

// MARK: - Presented State

public enum SRKScene: Equatable {
    case loading            // splash while pipeline is running
    case main               // host app main screen
    case web(url: String)   // WebView with the received URL
}

// MARK: - ViewModel

@MainActor
public final class SRKViewModel: ObservableObject {

    // MARK: Published

    @Published public internal(set) var presented: SRKScene = .loading

    // MARK: Internal

    /// Coordinator is created and retained here.
    /// A weak reference to self is passed to the coordinator.
    private var coordinator: SRKFlowCoordinator?

    // FCM updates after install — observe via NotificationCenter
    private var fcmObserver: NSObjectProtocol?

    // MARK: Init

    public init() {}

    deinit {
        if let obs = fcmObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Public API

    /// Called by ScreenRouterKit.shared.start() after configure()
    func begin(config: SRKConfiguration) {
        SRKLogger.log(.debug, "ViewModel: begin()")

        // Configure logger
        SRKLogger.mode = config.debugMode

        // Create coordinator
        let coord = SRKFlowCoordinator(config: config)
        coord.viewModel = self
        self.coordinator = coord

        // Subscribe to FCM token updates
        setupFCMObserver(config: config)

        // Start pipeline
        coord.start()
    }

    // MARK: - State Setters (called by Coordinator)

    func setLoading() {
        SRKLogger.log(.debug, "ViewModel: → loading")
        presented = .loading
    }

    func setMain() {
        SRKLogger.log(.info, "ViewModel: → main")
        presented = .main
    }

    func setWeb(url: String) {
        SRKLogger.log(.info, "ViewModel: → web(\(url))")
        presented = .web(url: url)
    }

    // MARK: - FCM Observer

    /// Observe FCM token updates arriving from AppDelegate via NotificationCenter
    /// If install was already done — send POST /sync with the new token
    private func setupFCMObserver(config: SRKConfiguration) {
        fcmObserver = NotificationCenter.default.addObserver(
            forName: .srkFCMTokenDidUpdate,
            object: nil,
            queue: nil
        ) { [weak self] note in
            guard let self else { return }

            let token = (note.userInfo?["token"] as? String)
                ?? UserDefaults.standard.string(forKey: "srk.fcm.token")
                ?? ""

            guard !token.isEmpty else { return }

            SRKLogger.log(.debug, "ViewModel: FCM updated — triggering refresh")
            SRKLogger.logKey(.fcmRefresh, "fcm=\(String(token))")

            // Store in PushGate for future requests
            SRKPushGate.shared.fcmToken = token

            Task { @MainActor [weak self] in
                guard let self, let coordinator = self.coordinator else { return }
                let deviceID = UserDefaults.standard.string(forKey: "srk.session.device") ?? ""
                guard !deviceID.isEmpty else { return }
                coordinator.tryRefreshIfNeeded(currentFCM: token, deviceID: deviceID)
            }
        }
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    /// Posted from AppDelegate when Firebase updates the FCM token.
    /// userInfo: ["token": String]
    static let srkFCMTokenDidUpdate = Notification.Name("srk.fcm.token.didUpdate")

    /// Posted from AppDelegate when APNs registers the device.
    /// userInfo: ["srk_apns": String (hex)]
    static let srkAPNSTokenDidUpdate = Notification.Name("srk.srk_apns.token.didUpdate")
}

