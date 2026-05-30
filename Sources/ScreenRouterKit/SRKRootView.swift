import SwiftUI
import Combine

final class SRKReadyGate {

    private var pipelineDone  = false
    private var splashDone    = false
    private var dismissAction: (() -> Void)?

    func pipelineReady(dismiss: @escaping () -> Void) {
        pipelineDone  = true
        dismissAction = dismiss
        tryDismiss()
    }

    func splashReady() {
        splashDone = true
        tryDismiss()
    }

    private func tryDismiss() {
        guard pipelineDone, splashDone else { return }
        dismissAction?()
        dismissAction = nil
    }

    func reset() {
        pipelineDone  = false
        splashDone    = false
        dismissAction = nil
    }
}

struct SRKRouterRootView: View {

    @EnvironmentObject private var vm: SRKRouterViewModel

    @State private var splashOpacity: Double  = 1
    @State private var splashOffset:  CGSize  = .zero
    @State private var splashScale:   CGFloat = 1
    @State private var splashVisible: Bool    = true

    @StateObject private var gate = SRKReadyGateHolder()

    init() {}

    var body: some View {
        ZStack {
            content

            if splashVisible {
                splashLayer
                    .opacity(splashOpacity)
                    .offset(splashOffset)
                    .scaleEffect(splashScale)
                    .ignoresSafeArea()
                    .zIndex(1)
            }
        }
        .onChange(of: vm.presented) {_, newState in
            switch newState {
            case .main, .web:
                gate.value.pipelineReady(dismiss: fadeOutSplash)
            case .loading:
                splashOpacity = 1
                splashOffset  = .zero
                splashScale   = 1
                splashVisible = true
                gate.value.reset()
            }
        }
    }

    @ViewBuilder
    private var splashLayer: some View {
        if let splash = ScreenRouterKit.shared.config?.splashProvider {
            splash {
                gate.value.splashReady()
                ScreenRouterKit.shared.splashSignal.complete()
            }
        } else {
            Color(.systemBackground)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.presented {
        case .loading:
            Color(.systemBackground).ignoresSafeArea()

        case .main:
            if let mainProvider = ScreenRouterKit.shared.mainViewProvider {
                mainProvider()
            } else {
                Color(.systemBackground).ignoresSafeArea()
            }

        case .web(let url):
            SRKWebContainerView(url: url)
                .onAppear {
                    SRKOrientationProxy.shared.set(
                        ScreenRouterKit.shared.config?.webOrientations ?? .all
                    )
                }
                .onDisappear {
                    SRKOrientationProxy.shared.set(
                        ScreenRouterKit.shared.config?.defaultOrientations ?? .portrait
                    )
                }
        }
    }

    private func fadeOutSplash() {
        guard splashVisible else { return }
        let config = ScreenRouterKit.shared.transitionConfig

        withAnimation(config.animation) {
            switch config.type {
            case .fade:
                splashOpacity = 0

            case .scale:
                splashOpacity = 0
                splashScale   = 1.15

            case .slide(let edge):
                let screen = (UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?.screen ?? UIScreen.main).bounds
                switch edge {
                case .up:    splashOffset = CGSize(width: 0, height: -screen.height)
                case .down:  splashOffset = CGSize(width: 0, height:  screen.height)
                case .left:  splashOffset = CGSize(width: -screen.width,  height: 0)
                case .right: splashOffset = CGSize(width:  screen.width,  height: 0)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            splashVisible = false
        }
    }
}

@MainActor
private final class SRKReadyGateHolder: ObservableObject {
    let value = SRKReadyGate()
}

final class SRKOrientationProxy {

    static let shared = SRKOrientationProxy()
    private init() {}

    func set(_ mask: UIInterfaceOrientationMask) {
        if #available(iOS 16.0, *) {
            UIApplication.shared.connectedScenes.forEach { scene in
                guard let windowScene = scene as? UIWindowScene else { return }
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
                windowScene.keyWindow?.rootViewController?
                    .setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        } else {
            let orientation: UIInterfaceOrientation = (
                mask == .landscapeLeft  ||
                mask == .landscapeRight ||
                mask == .landscape
            ) ? .landscapeRight : .portrait
            UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        }
        SRKLogger.log(.debug, "Orientation: \(mask.rawValue)")
    }
}

