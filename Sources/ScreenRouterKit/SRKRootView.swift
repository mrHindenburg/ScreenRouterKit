// SRKRootView.swift
// ScreenRouterKit

import SwiftUI

// MARK: - Root View

public struct SRKRootView: View {

    @EnvironmentObject private var vm: SRKViewModel

    @State private var splashOpacity: Double  = 1
    @State private var splashOffset:  CGSize  = .zero
    @State private var splashScale:   CGFloat = 1
    @State private var splashVisible: Bool    = true

    public init() {}

    public var body: some View {
        ZStack {
            // ── Main / Web content (rendered beneath splash) ─────────────
            content

            // ── Splash layer (transitions out on top) ─────────────────────
            if splashVisible {
                splashLayer
                    .opacity(splashOpacity)
                    .offset(splashOffset)
                    .scaleEffect(splashScale)
                    .ignoresSafeArea()
                    .zIndex(1)
            }
        }
        .onChange(of: vm.presented) { newState in
            let isSimpleMode = ScreenRouterKit.shared.config?.splashProviderSimple != nil

            switch newState {
            case .main, .web:
                if !isSimpleMode {
                    fadeOutSplash()
                }
            case .loading:
                splashOpacity = 1
                splashOffset  = .zero
                splashScale   = 1
                splashVisible = true
            }
        }
    }

    // MARK: - Splash Layer

    @ViewBuilder
    private var splashLayer: some View {
        let kit = ScreenRouterKit.shared

        if let splashSimple = kit.config?.splashProviderSimple {
            // Simple mode — SplashView calls onComplete() when animation finishes
            splashSimple {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    fadeOutSplash()
                }
            }
        } else if let splash = kit.config?.splashProvider {
            // Full mode — library dismisses splash when pipeline resolves
            splash()
        } else {
            Color(.systemBackground)
        }
    }

    // MARK: - Content (beneath splash)

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

    // MARK: - Dismiss

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
                switch edge {
                case .up:    splashOffset = CGSize(width: 0, height: -UIScreen.main.bounds.height)
                case .down:  splashOffset = CGSize(width: 0, height:  UIScreen.main.bounds.height)
                case .left:  splashOffset = CGSize(width: -UIScreen.main.bounds.width,  height: 0)
                case .right: splashOffset = CGSize(width:  UIScreen.main.bounds.width,  height: 0)
                }
            }
        }

        // Remove from hierarchy after animation completes
        let duration = animationDuration(config.animation)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
            splashVisible = false
        }
    }

    /// Extracts approximate duration from Animation for cleanup timing.
    private func animationDuration(_ animation: Animation) -> Double {
        // SwiftUI Animation doesn't expose duration directly —
        // we use a reasonable fallback that covers most cases.
        // Host can tune via SRKTransitionConfig.animation.
        return 0.7
    }
}

// MARK: - Orientation Proxy

public final class SRKOrientationProxy {

    public static let shared = SRKOrientationProxy()
    private init() {}

    public func set(_ mask: UIInterfaceOrientationMask) {
        if #available(iOS 16.0, *) {
            UIApplication.shared.connectedScenes.forEach { scene in
                guard let windowScene = scene as? UIWindowScene else { return }
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
            }
            UIViewController.attemptRotationToDeviceOrientation()
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
