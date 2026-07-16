@preconcurrency import SwiftUI
import Combine

enum SRKScene: Equatable {
    case loading
    case main
    case web(url: String)
}

@MainActor
final class SRKRouterViewModel: ObservableObject {

    @Published var presented: SRKScene = .loading

    private var coordinator: SRKFlowCoordinator?
    private var fcmObserver: NSObjectProtocol?

    init() {}

    deinit {
        if let obs = fcmObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    func begin(config: SRKConfiguration) {
        SRKLogger.mode = config.debugMode

        let coord = SRKFlowCoordinator(config: config)
        coord.viewModel = self
        self.coordinator = coord
        coord.start()
    }

    func setLoading() {
        presented = .loading
    }

    func setMain() {
        presented = .main
    }

    func setWeb(url: String) {
        presented = .web(url: url)
    }
}

public extension Notification.Name {
    static let wbcFCMTokenDidUpdate  = Notification.Name("wbc.fcm.token.didUpdate")
    static let wbcAPNSTokenDidUpdate = Notification.Name("wbc.apns.token.didUpdate")
}
