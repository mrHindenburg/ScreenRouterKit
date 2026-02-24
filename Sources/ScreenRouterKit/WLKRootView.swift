// WLKRootView.swift
// ScreenRouterKit

import SwiftUI

// MARK: - Root View

public struct WLKRootView: View {

    @EnvironmentObject private var vm: WLKViewModel

    // Controls the fade-out of the splash layer
    @State private var splashOpacity: Double = 1
    @State private var splashVisible: Bool   = true

    public init() {}

    public var body: some View {
        ZStack {

            // ── Main / Web content (always rendered beneath splash) ───────
            content

            // ── Splash layer (fades out on top) ───────────────────────────
            if splashVisible {
                splashLayer
                    .opacity(splashOpacity)
                    .ignoresSafeArea()
                    .zIndex(1)
            }
        }
        .onChange(of: vm.presented) { newState in
            switch newState {
            case .main, .web:
                fadeOutSplash()
            case .loading:
                // Reset if library is restarted
                splashOpacity = 1
                splashVisible = true
            }
        }
    }

    // MARK: - Splash Layer

    @ViewBuilder
    private var splashLayer: some View {
        if let splash = ScreenRouterKit.shared.config?.splashProvider {
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
            WLKWebContainerView(url: url)
                .onAppear {
                    WLKOrientationProxy.shared.set(
                        ScreenRouterKit.shared.config?.webOrientations ?? .all
                    )
                }
                .onDisappear {
                    WLKOrientationProxy.shared.set(
                        ScreenRouterKit.shared.config?.defaultOrientations ?? .portrait
                    )
                }
        }
    }

    // MARK: - Fade

    private func fadeOutSplash() {
        withAnimation(.easeInOut(duration: 0.6)) {
            splashOpacity = 0
        }
        // Remove from hierarchy after fade completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            splashVisible = false
        }
    }
}

// MARK: - Orientation Proxy

public final class WLKOrientationProxy {

    public static let shared = WLKOrientationProxy()
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
        WLKLogger.log(.debug, "Orientation: \(mask.rawValue)")
    }
}
