// WLKViewModel.swift
// ScreenRouterKit

import SwiftUI
import Combine

// MARK: - Presented State

public enum WLKPresented: Equatable {
    case loading            // splash while pipeline is running
    case main               // host app main screen
    case web(url: String)   // WebView with the received URL
}

// MARK: - ViewModel

@MainActor
public final class WLKViewModel: ObservableObject {

    // MARK: Published

    @Published public internal(set) var presented: WLKPresented = .loading

    // MARK: Internal

    /// Coordinator is created and retained here.
    /// A weak reference to self is passed to the coordinator.
    private var coordinator: WLKLifecycleCoordinator?

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
    func begin(config: WLKConfiguration) {
        WLKLogger.log(.debug, "ViewModel: begin()")

        // Configure logger
        WLKLogger.mode = config.debugMode

        // Create coordinator
        let coord = WLKLifecycleCoordinator(config: config)
        coord.viewModel = self
        self.coordinator = coord

        // Subscribe to FCM token updates
        setupFCMObserver(config: config)

        // Start pipeline
        coord.start()
    }

    // MARK: - State Setters (called by Coordinator)

    func setLoading() {
        WLKLogger.log(.debug, "ViewModel: → loading")
        presented = .loading
    }

    func setMain() {
        WLKLogger.log(.info, "ViewModel: → main")
        presented = .main
    }

    func setWeb(url: String) {
        WLKLogger.log(.info, "ViewModel: → web(\(url))")
        presented = .web(url: url)
    }

    // MARK: - FCM Observer

    /// Observe FCM token updates arriving from AppDelegate via NotificationCenter
    /// If install was already done — send POST /refresh with the new token
    private func setupFCMObserver(config: WLKConfiguration) {
        fcmObserver = NotificationCenter.default.addObserver(
            forName: .wlkFCMTokenDidUpdate,
            object: nil,
            queue: nil
        ) { [weak self] note in
            guard let self else { return }

            let token = (note.userInfo?["token"] as? String)
                ?? UserDefaults.standard.string(forKey: "fcmToken")
                ?? ""

            guard !token.isEmpty else { return }

            WLKLogger.log(.debug, "ViewModel: FCM updated — triggering refresh")

            // Store in PushGate for future requests
            WLKPushGate.shared.fcmToken = token

            Task { @MainActor [weak self] in
                guard let self, let coordinator = self.coordinator else { return }
                let deviceID = UserDefaults.standard.string(forKey: "wlk.install.device") ?? ""
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
    static let wlkFCMTokenDidUpdate = Notification.Name("wlk.fcm.token.didUpdate")

    /// Posted from AppDelegate when APNs registers the device.
    /// userInfo: ["apns": String (hex)]
    static let wlkAPNSTokenDidUpdate = Notification.Name("wlk.apns.token.didUpdate")
}
