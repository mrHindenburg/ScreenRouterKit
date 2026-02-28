// SRKRootView.swift
// ScreenRouterKit

import SwiftUI

// MARK: - Ready Gate

/// Waits for BOTH conditions before dismissing splash:
///   1. Pipeline resolved (vm.presented changed to .main or .web)
///   2. SplashView called onComplete() — animation finished
///
/// Whichever happens first — waits for the other.
/// Guarantees splash is never cut short even if server responds instantly.

final class SRKReadyGate {

    private var pipelineDone  = false
    private var splashDone    = false
    private var dismissAction: (() -> Void)?

    /// Call when routing pipeline finishes.
    func pipelineReady(dismiss: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.pipelineDone  = true
            self.dismissAction = dismiss
            self.tryDismiss()
        }
    }

    /// Call when SplashView's onComplete() fires.
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

// MARK: - Root View

public struct SRKRootView: View {

    @EnvironmentObject private var vm: SRKViewModel

    @State private var splashOpacity: Double  = 1
    @State private var splashOffset:  CGSize  = .zero
    @State private var splashScale:   CGFloat = 1
    @State private var splashVisible: Bool    = true

    // ReadyGate lives here — one per RootView lifecycle
    @StateObject private var gate = ReadyGateHolder()

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
            switch newState {
            case .main, .web:
                // Pipeline done — gate dismisses when splash also calls onComplete()
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

    // MARK: - Splash Layer

    @ViewBuilder
    private var splashLayer: some View {
        if let splash = ScreenRouterKit.shared.config?.splashProvider {
            // Same SplashView for ALL modes.
            // onComplete() → gate.splashReady() → dismiss when pipeline also done.
            // In simple mode: pipeline resolves instantly → dismiss fires when splash calls onComplete().
            // In full mode:   if server is fast → waits for splash; if splash is fast → waits for server.
            splash {
                gate.value.splashReady()
            }
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            splashVisible = false
        }
    }
}

// MARK: - ReadyGate Holder

/// Wraps SRKReadyGate in ObservableObject so @StateObject keeps it alive
/// for the full lifetime of SRKRootView.
private final class ReadyGateHolder: ObservableObject {
    let value = SRKReadyGate()
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
